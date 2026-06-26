import SwiftUI

/// A captured vehicle turned into a collectible card.
struct SpotCard: Identifiable, Hashable {
    var id = UUID()
    var make: String
    var model: String
    var year: Int
    var rarity: Rarity
    var colorName: String
    /// SF Symbol used when no (anonymized) photo is available yet.
    var symbol: String

    // Technical scores (0...100) derived from real specs.
    var power: Int
    var agility: Int
    var presence: Int

    var spottedArea: String
    var spottedDaysAgo: Int

    /// Anonymized capture, when the card came from a real spot.
    var imageData: Data? = nil

    var title: String { "\(make) \(model)" }
}

extension SpotCard {
    static let sample: [SpotCard] = [
        SpotCard(make: "Lancia", model: "Delta Integrale", year: 1992,
                 rarity: .leggendaria, colorName: "Rosso Monza", symbol: "car.side.fill",
                 power: 88, agility: 82, presence: 96,
                 spottedArea: "Centro Storico", spottedDaysAgo: 0),
        SpotCard(make: "Alfa Romeo", model: "Giulia Quadrifoglio", year: 2023,
                 rarity: .epica, colorName: "Verde Montreal", symbol: "car.fill",
                 power: 92, agility: 78, presence: 85,
                 spottedArea: "Lungomare", spottedDaysAgo: 1),
        SpotCard(make: "Volkswagen", model: "Golf GTI", year: 2019,
                 rarity: .rara, colorName: "Bianco Puro", symbol: "car.fill",
                 power: 70, agility: 80, presence: 60,
                 spottedArea: "Stazione", spottedDaysAgo: 2),
        SpotCard(make: "Fiat", model: "Panda", year: 2014,
                 rarity: .comune, colorName: "Grigio Moda", symbol: "car.fill",
                 power: 28, agility: 95, presence: 22,
                 spottedArea: "Quartiere Nord", spottedDaysAgo: 3),
        SpotCard(make: "Porsche", model: "911 Carrera", year: 2021,
                 rarity: .leggendaria, colorName: "Argento GT", symbol: "car.side.fill",
                 power: 95, agility: 76, presence: 93,
                 spottedArea: "Collina", spottedDaysAgo: 4),
        SpotCard(make: "Mini", model: "Cooper S", year: 2017,
                 rarity: .rara, colorName: "British Racing", symbol: "car.fill",
                 power: 64, agility: 88, presence: 58,
                 spottedArea: "Centro Storico", spottedDaysAgo: 5)
    ]
}

/// A daily objective shown on the Today screen.
struct DailyChallenge: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var progress: Int
    var goal: Int
    var reward: Int
    var done: Bool { progress >= goal }
}

extension DailyChallenge {
    static let sample: [DailyChallenge] = [
        DailyChallenge(icon: "bolt.car.fill", title: "Trova 2 auto elettriche", progress: 1, goal: 2, reward: 120),
        DailyChallenge(icon: "clock.arrow.circulate", title: "Un'auto immatricolata prima del 1990", progress: 0, goal: 1, reward: 200),
        DailyChallenge(icon: "paintpalette.fill", title: "Scansiona un colore insolito", progress: 1, goal: 1, reward: 80)
    ]
}
