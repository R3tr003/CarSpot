import Foundation

/// Ritmo di gioco: catture a settimana negli ultimi 28 giorni. L'indice (0/1/2) sceglie l'obiettivo.
enum MissionPace: String, Sendable, CaseIterable {
    case occasional, regular, hunter

    var index: Int { MissionPace.allCases.firstIndex(of: self) ?? 0 }
}

/// Stile di gioco: cosa colleziona di più.
enum PlayerStyle: String, Sendable, CaseIterable {
    case rarity, vintage, explorer, brand, generalist
}

/// Gruppo del giocatore (Ritmo x Stile), calcolato dalle carte *prima* dell'inizio del periodo:
/// così le missioni non cambiano a metà e sono uguali su un altro telefono.
struct PlayerGroup: Sendable, Hashable {
    let pace: MissionPace
    let style: PlayerStyle

    /// Carte minime per avere uno stile.
    static let minCardsForStyle = 10

    /// Solo carte non ripetizione con `capturedAt < start`.
    static func compute(cards: [MissionCard], before start: Date, calendar: Calendar) -> PlayerGroup {
        let past = cards.filter { !$0.isRepeat && $0.capturedAt < start }
        return PlayerGroup(pace: pace(past, before: start, calendar: calendar), style: style(past))
    }

    /// Catture negli ultimi 28 giorni / 4 = a settimana: < 5 occasionale, < 20 abituale, altrimenti cacciatore.
    private static func pace(_ past: [MissionCard], before start: Date, calendar: Calendar) -> MissionPace {
        let from = calendar.date(byAdding: .day, value: -28, to: start) ?? start.addingTimeInterval(-28 * 86_400)
        let weekly = Double(past.filter { $0.capturedAt >= from }.count) / 4
        if weekly >= 20 { return .hunter }
        if weekly >= 5 { return .regular }
        return .occasional
    }

    /// Vince il punteggio (quota / soglia) >= 1 più alto; a parità l'ordine rarity, vintage, explorer, brand.
    private static func style(_ past: [MissionCard]) -> PlayerStyle {
        guard past.count >= minCardsForStyle else { return .generalist }
        let total = Double(past.count)

        let epicShare = Double(past.filter { $0.rarity.missionRank >= Rarity.epica.missionRank }.count) / total
        let vintageShare = Double(past.filter { $0.year > 0 && $0.year < 1990 }.count) / total
        let areas = Set(past.map(\.areaKey).filter { !$0.isEmpty }).count
        var makeCounts: [String: Int] = [:]
        for card in past where !card.makeKey.isEmpty { makeCounts[card.makeKey, default: 0] += 1 }
        let topMake = Double(makeCounts.values.max() ?? 0) / total

        let scores: [(PlayerStyle, Double)] = [
            (.rarity, epicShare / 0.15),
            (.vintage, vintageShare / 0.30),
            (.explorer, areas >= 5 ? (Double(areas) / total) / 0.50 : 0),
            (.brand, topMake / 0.40),
        ]
        var best: (style: PlayerStyle, score: Double)?
        for (style, score) in scores where score >= 1 {
            if best == nil || score > best!.score { best = (style, score) }
        }
        return best?.style ?? .generalist
    }
}
