import Foundation

/// Una missione con il suo progresso e lo stato di riscatto, pronta per la riga in Oggi.
struct MissionStatus: Identifiable, Sendable, Hashable {
    let mission: Mission
    /// min(obiettivo, progresso della regola nel periodo).
    let progress: Int
    let claimed: Bool
    /// Identità non vista e non riscattata (pallino verde).
    let isNew: Bool

    var id: String { mission.id }
    var done: Bool { progress >= mission.goal }
    var claimable: Bool { done && !claimed }
}

/// Un segmento del selettore (Oggi, Settimana, Mese, Comuni).
struct MissionSegment: Sendable, Identifiable {
    let kind: MissionPeriodKind
    let current: [MissionStatus]
    /// Periodi precedenti ancora in finestra di riscatto: solo missioni da riscattare.
    let leftovers: [MissionStatus]
    /// Fine del periodo corrente; nil per le comuni (ognuna ha la sua).
    let endsAt: Date?

    var id: MissionPeriodKind { kind }
    /// Da riscattare, periodo corrente e avanzi (pallino rosso).
    var claimableCount: Int { current.filter(\.claimable).count + leftovers.filter(\.claimable).count }
    /// Nuove, solo del periodo corrente (pallino verde).
    var newCount: Int { current.filter(\.isNew).count }
}

/// Tabellone delle missioni per la UI: logica pura, da chiamare fuori dal `body`.
enum MissionBoard {
    /// Ordine: day, week, month, community.
    static func build(cards: [MissionCard], ownerId: String, claimed: Set<String>, seen: Set<String>,
                      community: [CommunityMission], region: String?, now: Date,
                      calendar: Calendar) -> [MissionSegment] {
        func status(_ mission: Mission) -> MissionStatus {
            let value = mission.rule.progress(cards: cards, from: mission.period.start, to: mission.period.end)
            let isClaimed = claimed.contains(mission.id)
            return MissionStatus(mission: mission, progress: min(mission.goal, value), claimed: isClaimed,
                                 isNew: !isClaimed && !seen.contains(mission.id))
        }

        var segments: [MissionSegment] = [MissionPeriodKind.day, .week, .month].map { kind in
            let period = MissionPeriod.containing(now, kind: kind, calendar: calendar)
            let current = MissionEngine.personal(for: period, ownerId: ownerId, cards: cards, calendar: calendar)
                .map(status)

            // Avanzi: periodi finiti la cui finestra di riscatto è ancora aperta.
            var leftovers: [MissionStatus] = []
            var earlier = period.previous(calendar: calendar)
            while now < earlier.claimDeadline {
                leftovers += MissionEngine.personal(for: earlier, ownerId: ownerId, cards: cards, calendar: calendar)
                    .map(status)
                    .filter(\.claimable)
                earlier = earlier.previous(calendar: calendar)
            }
            return MissionSegment(kind: kind, current: current, leftovers: leftovers, endsAt: period.end)
        }

        let all = community
            .filter { $0.isVisible(region: region) }
            .compactMap { $0.mission(calendar: calendar) }
        let active = all.filter { $0.period.start <= now && now < $0.period.end }.map(status)
        let finished = all.filter { $0.period.end <= now && now < $0.period.claimDeadline }
            .map(status)
            .filter(\.claimable)
        segments.append(MissionSegment(kind: .community, current: active, leftovers: finished, endsAt: nil))
        return segments
    }
}
