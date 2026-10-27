import Foundation
import SwiftData

/// The player's progression state. A single row, created on first launch.
@Model
final class PlayerProfile {
    var xp: Int = 0
    var currency: Int = 0
    var streak: Int = 1
    var lastActiveDay: String = ""           // "yyyy-MM-dd"
    /// Vecchi obiettivi del giorno: non più usato, resta per la migrazione leggera.
    var claimedChallenges: [String] = []
    /// Id Clerk a cui appartengono questi progressi; "" = mai associato a un account.
    var ownerId: String = ""
    /// Vecchi riscatti in coda: non più usato, resta per la migrazione leggera.
    var pendingClaims: [String] = []
    /// Identità (`Mission.id`) delle missioni già riscattate.
    var claimedMissions: [String] = []
    /// Riscatti di missioni non ancora inviati al cloud (JSON di `MissionClaimPayload`).
    var pendingMissionClaims: [String] = []
    /// Identità delle missioni già viste in Oggi (spegne il pallino "nuova").
    var seenMissions: [String] = []
    /// Badge ottenuti (id del modello/missione).
    var badges: [String] = []

    init() {
        lastActiveDay = Self.dayKey()
    }

    var level: Int { LevelSystem.level(forXP: xp) }

    /// Riparte da zero per un nuovo proprietario (cambio account / primo login).
    func resetForOwner(_ id: String) {
        xp = 0
        currency = 0
        streak = 1
        claimedChallenges = []
        pendingClaims = []
        claimedMissions = []
        pendingMissionClaims = []
        seenMissions = []
        badges = []
        ownerId = id
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        // Chiave interna: stabile, indipendente dalla lingua e dal calendario del telefono.
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}

/// XP curve and level math. Each level costs a bit more than the last.
enum LevelSystem {
    /// XP required to go from `level` to `level + 1`.
    static func step(_ level: Int) -> Int { 100 + (level - 1) * 60 }

    /// Cumulative XP needed to reach `level`.
    static func xpToReach(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + step($1) }
    }

    static func level(forXP xp: Int) -> Int {
        var lvl = 1
        while xp >= xpToReach(lvl + 1) { lvl += 1 }
        return lvl
    }

    /// Progress within the current level.
    static func progress(forXP xp: Int) -> (level: Int, into: Int, needed: Int, fraction: Double) {
        let lvl = level(forXP: xp)
        let base = xpToReach(lvl)
        let needed = step(lvl)
        let into = xp - base
        return (lvl, into, needed, needed > 0 ? Double(into) / Double(needed) : 0)
    }
}

/// Rewards for adding a card, by rarity.
extension Rarity {
    var xpReward: Int {
        switch self {
        case .comune: return 20
        case .rara: return 55
        case .epica: return 130
        case .leggendaria: return 260
        }
    }
    var currencyReward: Int { xpReward / 4 }
}

@MainActor
enum PlayerStore {
    /// Fetches (creating if needed) the single player profile.
    static func profile(_ context: ModelContext) -> PlayerProfile {
        if let existing = try? context.fetch(FetchDescriptor<PlayerProfile>()).first {
            return existing
        }
        let p = PlayerProfile()
        context.insert(p)
        try? context.save()
        return p
    }

    static func award(xp: Int, currency: Int, in context: ModelContext) {
        let p = profile(context)
        let levelBefore = p.level
        p.xp += xp
        p.currency += currency
        try? context.save()
        trackLevelUp(from: levelBefore, to: p.level)
        reportProgress(context)
    }

    /// Un solo evento per salita, anche se un premio fa saltare più livelli.
    private static func trackLevelUp(from before: Int, to after: Int) {
        guard after > before else { return }
        AppServices.analytics.track(.levelUp(level: after))
    }

    /// Carte del giocatore ridotte ai dati che servono alle missioni.
    static func missionCards(_ context: ModelContext) -> [MissionCard] {
        ((try? context.fetch(FetchDescriptor<StoredCard>())) ?? []).map(MissionCard.init)
    }

    /// Gauge di progressione per le dashboard: livello, PE e missioni del giorno completate.
    /// Aggiorna anche la serie (calcolata dalle carte). Si chiama dopo ogni cambio
    /// rilevante (cattura, riscatto) e all'avvio.
    static func reportProgress(_ context: ModelContext) {
        let p = profile(context)
        let cards = missionCards(context)
        let calendar = Calendar.missions
        let now = Date.now

        let day = MissionBoard.build(
            cards: cards, ownerId: p.ownerId, claimed: Set(p.claimedMissions), seen: Set(p.seenMissions),
            community: [], region: nil, now: now, calendar: calendar
        ).first { $0.kind == .day }
        let completed = day?.current.filter(\.done).count ?? 0

        let captures = cards.map { StreakCapture(capturedAt: $0.capturedAt, rarity: $0.rarity, isRepeat: $0.isRepeat) }
        let streak = StreakCalculator.state(captures: captures, now: now, calendar: calendar).count
        if p.streak != streak {
            p.streak = streak
            try? context.save()
        }

        let errors = AppServices.errors
        errors.metric(gauge: "player.level", value: Double(p.level))
        errors.metric(gauge: "player.xp", value: Double(p.xp))
        errors.metric(gauge: "challenge.progress", value: Double(completed))
        // Profilo utente Mixpanel: stessi punti di aggiornamento (cattura, riscatto, avvio).
        AnalyticsProfileSync.refresh(in: context)
    }

    /// Riscatta una missione completata una sola volta, assegnando il premio in locale.
    /// Il server ricalcola e decide al push (`SyncService.didClaimMission`).
    @discardableResult
    static func claim(_ status: MissionStatus, in context: ModelContext) -> Bool {
        guard status.claimable else { return false }
        let p = profile(context)
        let mission = status.mission
        guard !p.claimedMissions.contains(mission.id) else { return false }
        let levelBefore = p.level
        p.claimedMissions.append(mission.id)
        p.xp += mission.reward
        p.currency += mission.reward / 4
        if let badge = mission.badgeId, !p.badges.contains(badge) {
            p.badges.append(badge)
        }
        try? context.save()
        trackLevelUp(from: levelBefore, to: p.level)
        AppServices.errors.metric(count: "challenge.claimed")
        reportProgress(context)
        return true
    }

    /// Annulla in locale un riscatto rifiutato dal server o scaduto prima dell'invio:
    /// toglie identità e badge e ritira il premio (mai sotto zero). Senza `reward`
    /// (payload di una versione precedente) si toglie solo il riscatto.
    static func revertClaim(_ payload: MissionClaimPayload, in context: ModelContext) {
        let p = profile(context)
        p.claimedMissions.removeAll { $0 == payload.identity }
        if let badge = payload.badgeId { p.badges.removeAll { $0 == badge } }
        if let reward = payload.reward {
            p.xp = max(0, p.xp - reward)
            p.currency = max(0, p.currency - reward / 4)
        }
        try? context.save()
        reportProgress(context)
    }

    /// Segna come viste le missioni mostrate; tiene solo le ultime 300.
    static func markSeen(_ ids: [String], in context: ModelContext) {
        let p = profile(context)
        var known = Set(p.seenMissions)
        let fresh = ids.filter { known.insert($0).inserted }
        guard !fresh.isEmpty else { return }
        p.seenMissions = Array((p.seenMissions + fresh).suffix(300))
        try? context.save()
    }
}
