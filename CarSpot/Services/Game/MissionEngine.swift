import Foundation

/// Da dove viene una missione.
enum MissionSource: Sendable, Hashable {
    case personal
    case community(scope: String)
}

/// Missione concreta di un periodo: regola con i parametri già applicati, obiettivo e premio.
struct Mission: Identifiable, Sendable, Hashable {
    /// `period.identity(missionId)`: chiave del riscatto, uguale su ogni telefono.
    let id: String
    /// Id del modello o della missione comune.
    let missionId: String
    let period: MissionPeriod
    let source: MissionSource
    /// SF Symbol.
    let icon: String
    let title: String
    let rule: MissionRule
    let goal: Int
    let reward: Int
    let params: MissionParams?
    /// Mensili: "month:yyyy-MM|<id>"; comuni: dalla riga.
    let badgeId: String?
}

/// Generatore delle missioni personali: stesso giocatore + stesso periodo = stesse missioni.
enum MissionEngine {
    private static let fallbackMakes = ["Fiat", "Volkswagen", "BMW", "Alfa Romeo", "Porsche"]
    private static let decades = Array(stride(from: 1950, through: 2010, by: 10))

    static func personal(for period: MissionPeriod, ownerId: String, cards: [MissionCard],
                         calendar: Calendar) -> [Mission] {
        let slots = MissionCatalog.slots(for: period.kind)
        guard !slots.isEmpty else { return [] }

        // Solo carte prima dell'inizio: le missioni non cambiano a metà periodo.
        let past = cards.filter { !$0.isRepeat && $0.capturedAt < period.start }
        let group = PlayerGroup.compute(cards: past, before: period.start, calendar: calendar)
        let owner = ownerId.isEmpty ? "guest" : ownerId
        var rng = StableRandom(seed: "\(owner)|\(period.kind.rawValue)|\(period.startKey)")

        var chosen: [MissionTemplate] = []
        var missions: [Mission] = []
        for slot in slots {
            let candidates = MissionCatalog.pool.filter { template in
                template.kind == period.kind && template.slot == slot
                    && !chosen.contains { $0.id == template.id }
            }
            guard let template = pick(candidates, style: group.style, rng: &rng) else { continue }
            chosen.append(template)

            let params = parameters(for: template, past: past, rng: &rng)
            let goal = template.goal(for: group.pace)
            missions.append(Mission(
                id: period.identity(template.id),
                missionId: template.id,
                period: period,
                source: .personal,
                icon: template.icon,
                title: template.title(goal: goal, params: params),
                rule: template.rule(with: params),
                goal: goal,
                reward: template.reward(goal: goal),
                params: params,
                badgeId: template.badge ? "month:\(period.startKey.prefix(7))|\(template.id)" : nil
            ))
        }
        return missions
    }

    /// Estrazione pesata: peso 3 se lo stile del modello coincide con quello del giocatore, altrimenti 1.
    private static func pick(_ candidates: [MissionTemplate], style: PlayerStyle,
                             rng: inout StableRandom) -> MissionTemplate? {
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { $0.styles.contains(style) ? 3 : 1 }
        var roll = Int(rng.next() % UInt64(weights.reduce(0, +)))
        for (template, weight) in zip(candidates, weights) {
            if roll < weight { return template }
            roll -= weight
        }
        return candidates.last
    }

    /// Parametri dei modelli parametrici, scelti in modo deterministico da seme e carte passate.
    private static func parameters(for template: MissionTemplate, past: [MissionCard],
                               rng: inout StableRandom) -> MissionParams? {
        switch template.param {
        case .decade:
            // Meglio un decennio ancora senza carte: spinge verso il nuovo.
            let covered = Set(past.filter { $0.year > 0 }.map { $0.year / 10 * 10 })
            let free = decades.filter { !covered.contains($0) }
            let options = free.isEmpty ? decades : free
            return MissionParams(decade: options[Int(rng.next() % UInt64(options.count))])
        case .make:
            if let top = topMake(past) { return MissionParams(make: top) }
            return MissionParams(make: fallbackMakes[Int(rng.next() % UInt64(fallbackMakes.count))])
        case nil:
            return nil
        }
    }

    /// Marca più frequente (a parità la chiave minore); stringa originale della carta più vecchia.
    private static func topMake(_ past: [MissionCard]) -> String? {
        var counts: [String: Int] = [:]
        for card in past where !card.makeKey.isEmpty { counts[card.makeKey, default: 0] += 1 }
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else {
            return nil
        }
        return past.filter { $0.makeKey == best }
            .min { ($0.capturedAt, $0.make) < ($1.capturedAt, $1.make) }?.make
    }
}
