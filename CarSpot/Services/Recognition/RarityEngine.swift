import Foundation

/// Derives game parameters (rarity, technical scores) from a real vehicle.
/// MVP heuristics: real specs (HP/weight/dimensions) will refine these later,
/// but the mapping is deterministic per make/model so a car always scores alike.
enum RarityEngine {

    struct Assessment: Sendable {
        var rarity: Rarity
        var power: Int
        var agility: Int
        var presence: Int
        var colorName: String
    }

    // Marques that skew exotic / collectible.
    private static let exotic: Set<String> = [
        "Ferrari", "Lamborghini", "Porsche", "Maserati", "Aston Martin",
        "McLaren", "Bentley", "Lancia"
    ]
    private static let sporty: Set<String> = [
        "Alfa Romeo", "Abarth", "BMW", "Audi", "Mercedes-AMG", "Mini"
    ]
    private static let cityCars: Set<String> = [
        "Fiat", "Renault", "Toyota", "Peugeot", "Citroën", "Opel", "Dacia"
    ]

    private static let palette = [
        "Rosso Monza", "Verde Montreal", "Bianco Puro", "Nero Carbonio",
        "Argento GT", "Blu Notte", "Grigio Moda", "Giallo Modena"
    ]

    static func assess(make: String, model: String, year: Int?) -> Assessment {
        let key = (make + model).lowercased()
        let h = stableHash(key)

        // Base profile by class.
        var power: Int, agility: Int, presence: Int
        var baseRarity: Rarity

        if exotic.contains(make) {
            power = 86; agility = 72; presence = 92; baseRarity = .epica
        } else if sporty.contains(make) || isHotModel(model) {
            power = 70; agility = 80; presence = 66; baseRarity = .rara
        } else if cityCars.contains(make) {
            power = 32; agility = 92; presence = 26; baseRarity = .comune
        } else {
            power = 52; agility = 60; presence = 48; baseRarity = .comune
        }

        // Deterministic jitter so cards feel individual (±8).
        power = clamp(power + Int(h % 17) - 8)
        agility = clamp(agility + Int((h / 17) % 17) - 8)
        presence = clamp(presence + Int((h / 289) % 17) - 8)

        // Vintage bumps rarity & presence.
        var rarity = baseRarity
        if let year {
            if year <= 1995 {
                rarity = bump(rarity, by: 2); presence = clamp(presence + 14)
            } else if year <= 2005 {
                rarity = bump(rarity, by: 1); presence = clamp(presence + 6)
            }
        }
        // Halo models become legendary.
        if isHaloModel(model) { rarity = .leggendaria; presence = clamp(presence + 8) }

        let color = palette[Int(h % UInt64(palette.count))]
        return Assessment(rarity: rarity, power: power, agility: agility,
                          presence: presence, colorName: color)
    }

    // MARK: helpers

    private static func isHotModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return ["gti", "cooper s", "competizione", "rs", "type r", "sti"].contains { m.contains($0) }
    }

    private static func isHaloModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return ["integrale", "quadrifoglio", "911", "m3", "m4", "gt3", "stradale"].contains { m.contains($0) }
    }

    private static func bump(_ r: Rarity, by steps: Int) -> Rarity {
        let order = Rarity.allCases
        guard let i = order.firstIndex(of: r) else { return r }
        return order[min(i + steps, order.count - 1)]
    }

    private static func clamp(_ v: Int) -> Int { max(8, min(100, v)) }

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}
