import Foundation
import SwiftData

/// Persisted collectible. The anonymized photo is stored inline (small JPEG) with
/// external storage so the DB stays light.
@Model
final class StoredCard {
    var id: UUID = UUID()
    var make: String = ""
    var model: String = ""
    var year: Int = 0
    var rarityRaw: String = Rarity.comune.rawValue
    var colorName: String = ""
    var power: Int = 0
    var agility: Int = 0
    var presence: Int = 0
    var spottedArea: String = ""
    var capturedAt: Date = Date.now

    @Attribute(.externalStorage) var photo: Data?

    init(make: String, model: String, year: Int, rarity: Rarity, colorName: String,
         power: Int, agility: Int, presence: Int, spottedArea: String,
         capturedAt: Date = .now, photo: Data? = nil) {
        self.make = make
        self.model = model
        self.year = year
        self.rarityRaw = rarity.rawValue
        self.colorName = colorName
        self.power = power
        self.agility = agility
        self.presence = presence
        self.spottedArea = spottedArea
        self.capturedAt = capturedAt
        self.photo = photo
    }

    var rarity: Rarity { Rarity(rawValue: rarityRaw) ?? .comune }

    /// Maps the persisted row to the presentation card used across the UI.
    var asSpotCard: SpotCard {
        SpotCard(
            id: id, make: make, model: model, year: year, rarity: rarity,
            colorName: colorName,
            symbol: presence >= 80 ? "car.side.fill" : "car.fill",
            power: power, agility: agility, presence: presence,
            spottedArea: spottedArea,
            spottedDaysAgo: max(0, Calendar.current.dateComponents([.day], from: capturedAt, to: .now).day ?? 0),
            imageData: photo
        )
    }
}

enum CardSeeder {
    /// Seeds a starter collection on first launch so the Collection isn't empty.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<StoredCard>())) ?? 0
        guard count == 0 else { return }
        for s in SpotCard.sample {
            let card = StoredCard(
                make: s.make, model: s.model, year: s.year, rarity: s.rarity,
                colorName: s.colorName, power: s.power, agility: s.agility,
                presence: s.presence, spottedArea: s.spottedArea,
                capturedAt: Calendar.current.date(byAdding: .day, value: -s.spottedDaysAgo, to: .now) ?? .now
            )
            context.insert(card)
        }
        try? context.save()
    }
}
