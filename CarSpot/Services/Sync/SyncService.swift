import Foundation
import SwiftData
import Supabase
import os

/// Sync cloud di carte e progressi. Unico scrittore di SwiftData per conto del cloud:
/// la UI legge sempre la cache locale (`@Query`), qui si inviano le carte in attesa e si
/// scaricano solo le differenze. `store == nil` (niente Supabase/Clerk) = sync spento.
/// Riscatto annullato (rifiutato dal server o scaduto): la UI lo mostra una volta e lo svuota.
struct ClaimRejection: Identifiable, Sendable, Equatable {
    /// Identità della missione (`Mission.id`).
    let id: String
    let title: String
    let reward: Int
    /// `true` = scaduto prima dell'invio; `false` = rifiutato dal server.
    let expired: Bool
}

@MainActor
@Observable
final class SyncService {
    /// Impostato da `CarSpotApp.init`; usato solo da `CaptureViewModel` (non è nell'environment).
    static var shared: SyncService?

    private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "sync")

    private static let pullInterval: TimeInterval = 15 * 60
    private static let cursorOverlap: TimeInterval = 5 * 60
    private static let pageSize = 500
    private static let maxConcurrentDownloads = 3

    private(set) var userId: String?
    /// Missioni comuni (cache su disco + ultimo pull): la UI le filtra per regione.
    private(set) var communityMissions: [CommunityMission] = CommunityMissionCache.load()

    /// Riscatti annullati da mostrare all'utente (`clearClaimRejections` dopo la lettura).
    private(set) var claimRejections: [ClaimRejection] = []

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let store: (any CloudStore)?

    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var isPushing = false
    @ObservationIgnored private var pushAgain = false
    /// Elementi (carte + riscatti) inviati con successo dall'ultimo `pushPending` concluso.
    @ObservationIgnored private var pushedCount = 0
    @ObservationIgnored private var lastPullAt: Date?
    /// Cresce a ogni modifica locale ottimistica (carta salvata, riscatto): un pull del
    /// profilo iniziato prima di una modifica non deve sovrascriverne i valori.
    @ObservationIgnored private var mutationEpoch = 0

    @ObservationIgnored private var photosInFlight: Set<UUID> = []
    @ObservationIgnored private var activeDownloads = 0

    init(container: ModelContainer, store: (any CloudStore)?) {
        self.container = container
        self.store = store
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Ciclo di vita

    /// Login: se i dati locali sono di un altro owner (o senza owner) si azzerano, poi pull completo.
    func signedIn(userId: String) async {
        guard store != nil else { return }
        if self.userId != userId { lastPullAt = nil }
        self.userId = userId

        let profile = PlayerStore.profile(context)
        let cards = (try? context.fetch(FetchDescriptor<StoredCard>())) ?? []
        let foreign = cards.filter { $0.ownerId != userId }
        if profile.ownerId != userId || !foreign.isEmpty {
            Self.log.notice("Dati locali di un altro owner: azzero prima del pull")
            // Cursori vecchi non valgono più: la cache locale riparte vuota.
            Self.clearCursor(for: profile.ownerId)
            Self.clearCursor(for: userId)
            foreign.forEach { context.delete($0) }
            profile.resetForOwner(userId)
            try? context.save()
        }
        await syncNow(force: true)
    }

    /// Logout esplicito: via carte e progressi locali (restano nel cloud).
    func signedOutExplicitly() {
        guard store != nil else { return }
        if let userId { Self.clearCursor(for: userId) }
        try? context.delete(model: StoredCard.self)
        PlayerStore.profile(context).resetForOwner("")
        try? context.save()
        userId = nil
        lastPullAt = nil
        mutationEpoch += 1
        Self.log.notice("Logout: dati locali rimossi")
    }

    // MARK: - Sync

    /// Invia le code, poi (con throttle di 15 min, salvo `force`) scarica carte, profilo e riscatti.
    func syncNow(force: Bool = false) async {
        guard let store, let userId, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await pushPending()
        guard self.userId == userId else { return }

        let due = force || lastPullAt.map { Date.now.timeIntervalSince($0) >= Self.pullInterval } ?? true
        guard due else { return }

        do {
            var pulledCards = 0
            try await AppServices.errors.measure("sync.pull", operation: "sync") {
                pulledCards = try await pullCards(store: store, userId: userId)
                try await pullProfile(store: store, userId: userId)
                try await pullMissionClaims(store: store, userId: userId)
                try await pullBadges(store: store, userId: userId)
                // Le missioni comuni sono accessorie: se falliscono il resto del pull vale.
                do {
                    try await pullCommunity(store: store, userId: userId)
                } catch {
                    Self.log.error("Pull missioni comuni non riuscito: \(error.localizedDescription, privacy: .public)")
                }
            }
            if self.userId == userId {
                lastPullAt = .now
                reportCollectionSize()
                AppServices.errors.log("sync completed", attributes: [
                    "pulled_cards": .int(pulledCards),
                    "pending": .int(pendingCount(userId: userId)),
                ])
            }
        } catch {
            Self.log.error("Pull non riuscito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .sync, step: "pull")
            Self.reportFailure(stage: "pull", error: error)
        }
    }

    /// Carta appena salvata in locale: la assegna all'utente e prova subito l'invio.
    func didSave(_ card: StoredCard) async {
        guard store != nil, let userId else { return }
        card.ownerId = userId
        card.syncState = .pending
        try? context.save()
        mutationEpoch += 1
        await pushPending()
    }

    /// Riscatto fatto in locale: va in coda e si prova subito l'invio.
    func didClaimMission(_ payload: MissionClaimPayload) async {
        guard store != nil, userId != nil, let json = Self.encode(payload) else { return }
        let profile = PlayerStore.profile(context)
        if !profile.pendingMissionClaims.contains(json) {
            profile.pendingMissionClaims.append(json)
            try? context.save()
        }
        mutationEpoch += 1
        await pushPending()
    }

    func clearClaimRejections() {
        claimRejections = []
    }

    /// Prova a svuotare le code; ritorna carte + riscatti ancora in attesa.
    func flushPending() async -> Int {
        guard store != nil, let userId else { return 0 }
        // Se un invio è già in corso lo si aspetta, altrimenti il conteggio sarebbe vecchio.
        while isPushing {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { break }
        }
        await pushPending()
        return pendingCount(userId: userId)
    }

    // MARK: - Foto (download lazy)

    /// Scarica la foto di una carta ripristinata dal cloud, una volta sola, max 3 alla volta.
    func loadPhotoIfNeeded(cardId: UUID) async {
        guard let store, !photosInFlight.contains(cardId) else { return }
        guard let path = cardNeedingPhoto(cardId) else { return }

        photosInFlight.insert(cardId)
        defer { photosInFlight.remove(cardId) }

        // Attesa cooperativa: se la vista sparisce (cancellazione) si esce senza scaricare.
        while activeDownloads >= Self.maxConcurrentDownloads {
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
        }
        activeDownloads += 1
        defer { activeDownloads -= 1 }

        do {
            // Task non strutturato: se la cella esce dallo schermo il download finisce
            // comunque e la foto resta in cache (una richiesta per carta, mai ripetuta).
            let data = try await Task.detached { try await store.downloadPhoto(path: path) }.value
            guard let card = fetchCard(cardId), card.photo == nil else { return }
            card.photo = data
            try? context.save()
        } catch {
            Self.log.error("Download foto fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .sync, step: "download_photo")
        }
    }

    // MARK: - Invio

    private func pushPending() async {
        guard let store, let userId else { return }
        if isPushing { pushAgain = true; return }
        isPushing = true
        defer { isPushing = false }
        dropLegacyClaims()
        // Si ripete se nel frattempo è arrivata un'altra carta/riscatto.
        pushedCount = 0
        await AppServices.errors.measure("sync.push", operation: "sync") {
            repeat {
                pushAgain = false
                guard await pushOnce(store: store, userId: userId) else { return }
            } while pushAgain
        }
        // Coda residua dopo ogni giro (0 = tutto inviato) e quanto è partito.
        guard self.userId == userId else { return }
        if pushedCount > 0 {
            AppServices.errors.metric(count: "sync.pushed", value: UInt(pushedCount))
        }
        AppServices.errors.metric(gauge: "sync.pending", value: Double(pendingCount(userId: userId)))
    }

    /// Vecchi riscatti degli obiettivi del giorno: l'endpoint è revocato lato server e non
    /// si possono convertire in missioni, quindi si scartano.
    private func dropLegacyClaims() {
        let profile = PlayerStore.profile(context)
        guard !profile.pendingClaims.isEmpty else { return }
        Self.log.notice("Scarto \(profile.pendingClaims.count) riscatti del vecchio formato")
        profile.pendingClaims = []
        try? context.save()
    }

    /// Un giro su carte e riscatti in attesa. `false` al primo errore (si ritenta al prossimo sync).
    private func pushOnce(store: any CloudStore, userId: String) async -> Bool {
        for card in pendingCards(userId: userId) {
            guard await push(card, store: store, userId: userId) else { return false }
        }
        return await pushClaims(store: store, userId: userId)
    }

    private func push(_ card: StoredCard, store: any CloudStore, userId: String) async -> Bool {
        // Valori copiati prima degli await: il modello può sparire (logout) nel frattempo.
        let id = card.id
        var photoPath = card.photoPath
        let photo = card.photo
        let make = card.make, model = card.model, year = card.year
        let rarity = card.rarityRaw, color = card.colorName
        let power = card.power, agility = card.agility, presence = card.presence
        let area = card.spottedArea, capturedAt = card.capturedAt, isRepeat = card.isRepeat

        do {
            if photoPath == nil, let photo {
                let path = "\(userId)/\(id.uuidString.lowercased()).jpg"
                try await store.uploadPhoto(photo, path: path)
                guard self.userId == userId else { return false }
                photoPath = path
                if let live = fetchCard(id) { live.photoPath = path; try? context.save() }
            }
            try await store.insertCard(CloudCard(
                id: id, ownerId: userId, make: make, model: model,
                year: year == 0 ? nil : year, rarity: rarity,
                colorName: color.isEmpty ? nil : color,
                power: power, agility: agility, presence: presence,
                photoPath: photoPath, spottedArea: area.isEmpty ? nil : area,
                capturedAt: capturedAt, isRepeat: isRepeat, createdAt: nil
            ))
            guard self.userId == userId else { return false }
            if let live = fetchCard(id) {
                live.syncState = .synced
                try? context.save()
            }
            pushedCount += 1
            return true
        } catch {
            Self.log.error("Invio carta fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .sync, step: "push_card")
            Self.reportFailure(stage: "push", error: error)
            return false
        }
    }

    private func pushClaims(store: any CloudStore, userId: String) async -> Bool {
        for json in PlayerStore.profile(context).pendingMissionClaims {
            guard let payload = Self.decode(json) else {
                // Riga illeggibile: inutile tenerla.
                Self.log.error("Riscatto in coda illeggibile, lo scarto")
                removePending(json)
                continue
            }
            if Date.now > payload.deadline {
                Self.log.notice("Riscatto scaduto, lo scarto: \(payload.identity, privacy: .public)")
                reject(payload, expired: true)
            } else {
                do {
                    try await store.insertMissionClaim(CloudMissionClaim(payload))
                    pushedCount += 1
                } catch let error as PostgrestError where error.code == "P0001" {
                    // Rifiutato dal server: si annulla anche il premio locale (il pull riallinea i PE).
                    Self.log.notice("Riscatto rifiutato dal server: \(payload.identity, privacy: .public)")
                    guard self.userId == userId else { return false }
                    reject(payload, expired: false)
                } catch {
                    Self.log.error("Invio riscatto fallito: \(error.localizedDescription, privacy: .public)")
                    AppServices.errors.record(error, area: .sync, step: "push_claim")
                    Self.reportFailure(stage: "push", error: error)
                    return false
                }
            }
            guard self.userId == userId else { return false }
            removePending(json)
        }
        return true
    }

    /// Annulla il premio locale e segnala il riscatto perso alla UI.
    private func reject(_ payload: MissionClaimPayload, expired: Bool) {
        PlayerStore.revertClaim(payload, in: context)
        claimRejections.append(ClaimRejection(
            id: payload.identity, title: payload.title ?? "",
            reward: payload.reward ?? 0, expired: expired))
        AppServices.errors.metric(count: "mission.claim_rejected")
    }

    private func removePending(_ json: String) {
        let profile = PlayerStore.profile(context)
        profile.pendingMissionClaims.removeAll { $0 == json }
        try? context.save()
    }

    private static func encode(_ payload: MissionClaimPayload) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decode(_ json: String) -> MissionClaimPayload? {
        try? JSONDecoder().decode(MissionClaimPayload.self, from: Data(json.utf8))
    }

    // MARK: - Pull

    /// Ritorna quante carte nuove sono state inserite.
    private func pullCards(store: any CloudStore, userId: String) async throws -> Int {
        let allCards = (try? context.fetch(FetchDescriptor<StoredCard>())) ?? []
        var known = Set(allCards.map(\.id))
        // Senza carte locali il cursore non ha senso: pull completo.
        var cursor = allCards.isEmpty ? nil : Self.cursor(for: userId)
        let start = cursor.map { $0.addingTimeInterval(-Self.cursorOverlap) }
        var offset = 0
        var inserted = 0

        while true {
            let page = try await store.fetchCards(
                createdAfter: start, offset: offset, limit: Self.pageSize)
            guard self.userId == userId else { return inserted }

            for c in page where !known.contains(c.id) {
                context.insert(Self.makeCard(from: c, ownerId: userId))
                known.insert(c.id)
                inserted += 1
            }
            try? context.save()

            if let newest = page.compactMap(\.createdAt).max(), newest > (cursor ?? .distantPast) {
                cursor = newest
                Self.setCursor(newest, for: userId)
            }
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        return inserted
    }

    private func pullProfile(store: any CloudStore, userId: String) async throws {
        // Con carte/riscatti in attesa i valori locali ottimistici restano.
        guard pendingCount(userId: userId) == 0 else { return }
        let epoch = mutationEpoch
        guard let remote = try await store.fetchProfile(userId: userId) else { return }
        guard self.userId == userId, epoch == mutationEpoch,
              pendingCount(userId: userId) == 0 else { return }
        let profile = PlayerStore.profile(context)
        profile.xp = remote.xp
        profile.currency = remote.currency
        try? context.save()
    }

    /// Riscatti degli ultimi 40 giorni: le identità si aggiungono a `claimedMissions`.
    private func pullMissionClaims(store: any CloudStore, userId: String) async throws {
        let since = Calendar.missions.date(byAdding: .day, value: -40, to: .now) ?? .now
        let remote = try await store.fetchMissionClaims(sinceDay: PlayerProfile.dayKey(since))
        guard self.userId == userId else { return }
        let profile = PlayerStore.profile(context)
        var known = Set(profile.claimedMissions)
        var changed = false
        for claim in remote where known.insert(claim.identity).inserted {
            profile.claimedMissions.append(claim.identity)
            changed = true
        }
        if changed { try? context.save() }
    }

    private func pullBadges(store: any CloudStore, userId: String) async throws {
        let remote = try await store.fetchBadges()
        guard self.userId == userId else { return }
        let profile = PlayerStore.profile(context)
        var known = Set(profile.badges)
        var changed = false
        for badge in remote where known.insert(badge).inserted {
            profile.badges.append(badge)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Missioni comuni attive o finite da meno di 3 giorni; cache su disco per l'offline.
    private func pullCommunity(store: any CloudStore, userId: String) async throws {
        let since = Calendar.missions.date(byAdding: .day, value: -3, to: .now) ?? .now
        let remote = try await store.fetchCommunityMissions(endingAfter: PlayerProfile.dayKey(since))
        guard self.userId == userId else { return }
        CommunityMissionCache.save(remote)
        communityMissions = remote
    }

    // MARK: - Helper

    /// Gauge con il numero di carte in collezione (dopo il pull, quindi una volta per avvio e a ogni sync).
    private func reportCollectionSize() {
        let count = (try? context.fetchCount(FetchDescriptor<StoredCard>())) ?? 0
        AppServices.errors.metric(gauge: "collection.size", value: Double(count))
    }

    /// Metrica + log di un guasto di sync: `stage` (push | pull), tipo e codice dell'errore,
    /// mai il messaggio. Gli annullamenti non contano; l'offline conta ma è un warning.
    private static func reportFailure(stage: String, error: any Error) {
        let summary = ErrorSummary(error)
        guard !summary.isCancellation else { return }
        AppServices.errors.metric(count: "sync.failure", attributes: ["stage": .string(stage)])
        AppServices.errors.log("sync failed", level: summary.isConnectivity ? .warning : .error, attributes: [
            "stage": .string(stage),
            "error_type": .string(summary.type),
            "error_code": .string(summary.code),
        ])
    }

    private func pendingCards(userId: String) -> [StoredCard] {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.syncStateRaw == pending && $0.ownerId == userId },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func pendingCount(userId: String) -> Int {
        let profile = PlayerStore.profile(context)
        // `pendingClaims` (vecchio formato) conta: finché esiste, il pull non tocca i PE.
        return pendingCards(userId: userId).count + profile.pendingMissionClaims.count + profile.pendingClaims.count
    }

    private func fetchCard(_ id: UUID) -> StoredCard? {
        var descriptor = FetchDescriptor<StoredCard>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Path della foto da scaricare, se la carta esiste e la foto manca in locale.
    private func cardNeedingPhoto(_ id: UUID) -> String? {
        guard let card = fetchCard(id), card.photo == nil else { return nil }
        return card.photoPath
    }

    private static func makeCard(from c: CloudCard, ownerId: String) -> StoredCard {
        let card = StoredCard(
            make: c.make, model: c.model, year: c.year ?? 0,
            rarity: Rarity(rawValue: c.rarity) ?? .comune,
            colorName: c.colorName ?? "",
            power: c.power, agility: c.agility, presence: c.presence,
            spottedArea: c.spottedArea ?? "", capturedAt: c.capturedAt, photo: nil
        )
        card.id = c.id
        card.ownerId = ownerId
        card.photoPath = c.photoPath
        card.isRepeat = c.isRepeat ?? false
        card.syncState = .synced
        return card
    }

    // Cursore del pull per utente (max `created_at` visto).
    private static func cursorKey(_ userId: String) -> String { "sync.cursor.\(userId)" }

    private static func cursor(for userId: String) -> Date? {
        UserDefaults.standard.object(forKey: cursorKey(userId)) as? Date
    }

    private static func setCursor(_ date: Date, for userId: String) {
        UserDefaults.standard.set(date, forKey: cursorKey(userId))
    }

    private static func clearCursor(for userId: String) {
        guard !userId.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: cursorKey(userId))
    }
}
