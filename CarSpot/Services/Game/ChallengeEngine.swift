import Foundation

/// A daily objective resolved against the player's collection.
struct DailyChallengeVM: Identifiable {
    let id: String
    let icon: String
    let title: String
    let goal: Int
    let reward: Int
    let progress: Int
    let claimed: Bool

    var done: Bool { progress >= goal }
}

/// Generates the day's objectives (deterministic per day) and computes progress
/// from the captured cards. Pure logic — no storage.
enum ChallengeEngine {

    private struct Template {
        let id: String
        let icon: String
        let title: String
        let goal: Int
        let reward: Int
        let matches: (StoredCard) -> Bool
    }

    private static var pool: [Template] { [
        Template(id: "today2", icon: "camera.fill", title: String(localized: "Cattura 2 auto oggi"), goal: 2, reward: 120,
                 matches: { Calendar.current.isDateInToday($0.capturedAt) }),
        Template(id: "vintage", icon: "clock.arrow.circlepath", title: String(localized: "Trova un'auto prima del 1990"), goal: 1, reward: 200,
                 matches: { $0.year > 0 && $0.year < 1990 }),
        Template(id: "rarePlus", icon: "diamond.fill", title: String(localized: "Cattura una Rara o superiore"), goal: 1, reward: 90,
                 matches: { $0.rarity != .comune }),
        Template(id: "epic", icon: "hexagon.fill", title: String(localized: "Cattura un'auto Epica"), goal: 1, reward: 160,
                 matches: { $0.rarity == .epica || $0.rarity == .leggendaria }),
        Template(id: "trio", icon: "square.stack.3d.up.fill", title: String(localized: "Aggiungi 3 auto alla collezione"), goal: 3, reward: 110,
                 matches: { _ in true }),
        Template(id: "powerful", icon: "bolt.fill", title: String(localized: "Trova un'auto con 80+ di potenza"), goal: 1, reward: 130,
                 matches: { $0.power >= 80 })
    ] }

    /// The three objectives for `day`, with progress filled in from `cards`.
    static func today(cards: [StoredCard], claimed: [String], day: Date = .now) -> [DailyChallengeVM] {
        let key = PlayerProfile.dayKey(day)
        let seed = key.utf8.reduce(0) { $0 &+ Int($1) }
        let picks = pick(3, seed: seed)

        return picks.map { t in
            let progress = min(t.goal, cards.filter(t.matches).count)
            let claimedKey = "\(key)|\(t.id)"
            return DailyChallengeVM(id: t.id, icon: t.icon, title: t.title,
                                    goal: t.goal, reward: t.reward,
                                    progress: progress,
                                    claimed: claimed.contains(claimedKey))
        }
    }

    private static func pick(_ n: Int, seed: Int) -> [Template] {
        var chosen: [Template] = []
        var i = seed
        var used = Set<Int>()
        while chosen.count < n && used.count < pool.count {
            let idx = i % pool.count
            if !used.contains(idx) { used.insert(idx); chosen.append(pool[idx]) }
            i = i / 3 + 7
        }
        return chosen
    }
}
