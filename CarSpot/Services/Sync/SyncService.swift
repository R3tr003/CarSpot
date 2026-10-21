import Foundation
import SwiftData
import Supabase
import os

/// Sync cloud di carte e progressi. Unico scrittore di SwiftData per conto del cloud:
/// la UI legge sempre la cache locale (`@Query`), qui si inviano le carte in attesa e si
/// scaricano solo le differenze. `store == nil` (niente Supabase/Clerk) = sync spento.
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

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let store: (any CloudStore)?

    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var isPushing = false
    @ObservationIgnored private var pushAgain = false
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
            try await pullCards(store: store, userId: userId)
            try await pullProfile(store: store, userId: userId)
            try await pullClaims(store: store, userId: userId)
            if self.userId == userId { lastPullAt = .now }
        } catch {
            Self.log.error("Pull non riuscito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .sync, step: "pull")
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
    func didClaim(key: String) async {
        guard store != nil, userId != nil else { return }
        let profile = PlayerStore.profile(context)
        if !profile.pendingClaims.contains(key) {
            profile.pendingClaims.append(key)
            try? context.save()
        }
        mutationEpoch += 1
        await pushPending()
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
        // Si ripete se nel frattempo è arrivata un'altra carta/riscatto.
        repeat {
            pushAgain = false
            guard await pushOnce(store: store, userId: userId) else { return }
        } while pushAgain
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
        let area = card.spottedArea, capturedAt = card.capturedAt

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
                capturedAt: capturedAt, createdAt: nil
            ))
            guard self.userId == userId else { return false }
            if let live = fetchCard(id) {
                live.syncState = .synced
                try? context.save()
            }
            return true
        } catch {
            Self.log.error("Invio carta fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .sync, step: "push_card")
            return false
        }
    }

    private func pushClaims(store: any CloudStore, userId: String) async -> Bool {
        for key in PlayerStore.profile(context).pendingClaims {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            do {
                if parts.count == 2 {
                    try await store.insertClaim(CloudClaim(day: parts[0], challengeId: parts[1]))
                }
            } catch let error as PostgrestError where error.code == "P0001" {
                // Rifiutato dal server (giorno fuori finestra o tetto giornaliero): inutile ritentare.
                Self.log.notice("Riscatto rifiutato dal server, lo scarto: \(key, privacy: .public)")
            } catch {
                Self.log.error("Invio riscatto fallito: \(error.localizedDescription, privacy: .public)")
                AppServices.errors.record(error, area: .sync, step: "push_claim")
                return false
            }
            guard self.userId == userId else { return false }
            let profile = PlayerStore.profile(context)
            profile.pendingClaims.removeAll { $0 == key }
            try? context.save()
        }
        return true
    }

    // MARK: - Pull

    private func pullCards(store: any CloudStore, userId: String) async throws {
        let allCards = (try? context.fetch(FetchDescriptor<StoredCard>())) ?? []
        var known = Set(allCards.map(\.id))
        // Senza carte locali il cursore non ha senso: pull completo.
        var cursor = allCards.isEmpty ? nil : Self.cursor(for: userId)
        let start = cursor.map { $0.addingTimeInterval(-Self.cursorOverlap) }
        var offset = 0

        while true {
            let page = try await store.fetchCards(
                createdAfter: start, offset: offset, limit: Self.pageSize)
            guard self.userId == userId else { return }

            for c in page where !known.contains(c.id) {
                context.insert(Self.makeCard(from: c, ownerId: userId))
                known.insert(c.id)
            }
            try? context.save()

            if let newest = page.compactMap(\.createdAt).max(), newest > (cursor ?? .distantPast) {
                cursor = newest
                Self.setCursor(newest, for: userId)
            }
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
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

    private func pullClaims(store: any CloudStore, userId: String) async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let remote = try await store.fetchClaims(sinceDay: PlayerProfile.dayKey(yesterday))
        guard self.userId == userId else { return }
        let profile = PlayerStore.profile(context)
        var changed = false
        for claim in remote {
            let key = "\(claim.day)|\(claim.challengeId)"
            if !profile.claimedChallenges.contains(key) {
                profile.claimedChallenges.append(key)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    // MARK: - Helper

    private func pendingCards(userId: String) -> [StoredCard] {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.syncStateRaw == pending && $0.ownerId == userId },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func pendingCount(userId: String) -> Int {
        pendingCards(userId: userId).count + PlayerStore.profile(context).pendingClaims.count
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
