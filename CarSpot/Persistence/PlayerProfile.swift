import Foundation
import SwiftData

/// The player's progression state. A single row, created on first launch.
@Model
final class PlayerProfile {
    var xp: Int = 0
    var currency: Int = 0
    var streak: Int = 1
    var lastActiveDay: String = ""           // "yyyy-MM-dd"
    /// Keys of already-claimed daily challenges ("yyyy-MM-dd|challengeID").
    var claimedChallenges: [String] = []
    /// Id Clerk a cui appartengono questi progressi; "" = mai associato a un account.
    var ownerId: String = ""
    /// Riscatti non ancora inviati al cloud (stesse chiavi di `claimedChallenges`).
    var pendingClaims: [String] = []

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
        ownerId = id
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
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
        p.xp += xp
        p.currency += currency
        try? context.save()
    }

    /// Claims a completed daily challenge once, awarding its reward.
    @discardableResult
    static func claim(_ challenge: DailyChallengeVM, in context: ModelContext) -> Bool {
        guard challenge.done, !challenge.claimed else { return false }
        let p = profile(context)
        let key = "\(PlayerProfile.dayKey())|\(challenge.id)"
        guard !p.claimedChallenges.contains(key) else { return false }
        p.claimedChallenges.append(key)
        p.xp += challenge.reward
        p.currency += challenge.reward / 4
        try? context.save()
        return true
    }
}
