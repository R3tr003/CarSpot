import Foundation

/// Cosa si conta in una missione.
enum MissionCount: String, Codable, Sendable {
    case cards, models, makes, areas
}

/// Tipo di chiave che deve essere "nuova" (mai vista prima dell'inizio del periodo).
enum MissionFresh: String, Codable, Sendable {
    case model, make, area
}

/// Normalizzazione dei testi: gemella di `private.norm` e di `CardCopies` (minuscole,
/// spazi ai lati tolti, spazi interni ridotti a uno).
enum MissionText {
    static func norm(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Istantanea di una carta per le regole (niente SwiftData nella logica).
struct MissionCard: Sendable, Hashable {
    var make: String
    var model: String
    var year: Int
    var rarity: Rarity
    var power: Int
    var area: String
    var capturedAt: Date
    var isRepeat: Bool

    init(make: String, model: String, year: Int = 0, rarity: Rarity = .comune, power: Int = 0,
         area: String = "", capturedAt: Date, isRepeat: Bool = false) {
        self.make = make
        self.model = model
        self.year = year
        self.rarity = rarity
        self.power = power
        self.area = area
        self.capturedAt = capturedAt
        self.isRepeat = isRepeat
    }

    init(_ card: StoredCard) {
        self.init(make: card.make, model: card.model, year: card.year, rarity: card.rarity,
                  power: card.power, area: card.spottedArea, capturedAt: card.capturedAt,
                  isRepeat: card.isRepeat)
    }

    var makeKey: String { MissionText.norm(make) }
    var modelKey: String { "\(MissionText.norm(make))|\(MissionText.norm(model))" }
    var areaKey: String { MissionText.norm(area) }
}

extension Rarity {
    /// Posizione nella scala (comune 0 ... leggendaria 3).
    var missionRank: Int { Rarity.allCases.firstIndex(of: self) ?? 0 }
}

/// Regola di una missione come dati: stessa valutazione in Swift e in SQL
/// (`private.mission_progress`, migration 0011). Si cambiano sempre in coppia.
struct MissionRule: Codable, Sendable, Hashable {
    var count: MissionCount = .cards
    var minRarity: Rarity? = nil
    var yearFrom: Int? = nil
    var yearTo: Int? = nil
    var minPower: Int? = nil
    var makes: [String]? = nil
    var models: [String]? = nil
    var fresh: MissionFresh? = nil

    enum CodingKeys: String, CodingKey {
        case count
        case minRarity = "min_rarity"
        case yearFrom = "year_from"
        case yearTo = "year_to"
        case minPower = "min_power"
        case makes, models, fresh
    }

    /// La carta rispetta i vincoli (rarità, anni, potenza, marche, lista bersaglio)?
    func matches(_ card: MissionCard) -> Bool {
        if let minRarity, card.rarity.missionRank < minRarity.missionRank { return false }
        if yearFrom != nil || yearTo != nil {
            // Anno 0 = sconosciuto: non conta mai.
            guard card.year > 0 else { return false }
            if let yearFrom, card.year < yearFrom { return false }
            if let yearTo, card.year > yearTo { return false }
        }
        if let minPower, card.power < minPower { return false }
        if let makes, !makes.contains(card.makeKey) { return false }
        if let models {
            let key = card.modelKey
            guard models.contains(where: { key == $0 || key.hasPrefix($0 + " ") }) else { return false }
        }
        return true
    }

    /// Progresso nella finestra [from, to). Ripetizioni sempre escluse.
    func progress(cards: [MissionCard], from: Date, to: Date) -> Int {
        let real = cards.filter { !$0.isRepeat }

        // Chiavi già viste prima dell'inizio, per le regole "nuovo".
        var known = Set<String>()
        if let fresh {
            for card in real where card.capturedAt < from {
                if let key = Self.key(of: card, for: fresh) { known.insert(key) }
            }
        }

        let hits = real.filter { card in
            guard card.capturedAt >= from, card.capturedAt < to, matches(card) else { return false }
            guard let fresh else { return true }
            guard let key = Self.key(of: card, for: fresh) else { return false }
            return !known.contains(key)
        }

        switch count {
        case .cards:
            return hits.count
        case .models:
            return Set(hits.map(\.modelKey)).count
        case .makes:
            return Set(hits.map(\.makeKey).filter { !$0.isEmpty }).count
        case .areas:
            return Set(hits.map(\.areaKey).filter { !$0.isEmpty }).count
        }
    }

    /// Chiave della carta per il tipo "nuovo"; nil se vuota (area o marca mancanti).
    private static func key(of card: MissionCard, for fresh: MissionFresh) -> String? {
        let key: String
        switch fresh {
        case .model: key = card.modelKey
        case .make: key = card.makeKey
        case .area: key = card.areaKey
        }
        return key.isEmpty ? nil : key
    }
}

extension MissionRule {
    /// `count` assente nel JSON = `cards`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            count: try c.decodeIfPresent(MissionCount.self, forKey: .count) ?? .cards,
            minRarity: try c.decodeIfPresent(Rarity.self, forKey: .minRarity),
            yearFrom: try c.decodeIfPresent(Int.self, forKey: .yearFrom),
            yearTo: try c.decodeIfPresent(Int.self, forKey: .yearTo),
            minPower: try c.decodeIfPresent(Int.self, forKey: .minPower),
            makes: try c.decodeIfPresent([String].self, forKey: .makes),
            models: try c.decodeIfPresent([String].self, forKey: .models),
            fresh: try c.decodeIfPresent(MissionFresh.self, forKey: .fresh)
        )
    }
}
