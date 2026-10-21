import SwiftUI

/// Rarity is the spine of the visual system: the accent colour of any card,
/// badge or glow is derived from its rarity.
enum Rarity: String, CaseIterable, Identifiable, Codable {
    case comune = "Comune"
    case rara = "Rara"
    case epica = "Epica"
    case leggendaria = "Leggendaria"

    var id: String { rawValue }

    /// Nome mostrato all'utente. `rawValue` resta l'identificatore salvato (SwiftData, cloud).
    var displayName: LocalizedStringResource {
        switch self {
        case .comune: "Comune"
        case .rara: "Rara"
        case .epica: "Epica"
        case .leggendaria: "Leggendaria"
        }
    }

    /// Come `displayName`, ma già risolto in `String` (VoiceOver, annunci).
    var localizedName: String { String(localized: displayName) }

    /// Ordered gradient stops — cool steel → cyan → violet-magenta → gold.
    var gradient: [Color] {
        switch self {
        case .comune:      return [Color(hex: 0xB4BCCB), Color(hex: 0x8A93A6)]
        case .rara:        return [Color(hex: 0x36E2FF), Color(hex: 0x2A7DF0)]
        case .epica:       return [Color(hex: 0xC04BFF), Color(hex: 0xFF4D9D)]
        case .leggendaria: return [Color(hex: 0xFFE176), Color(hex: 0xFFA62B), Color(hex: 0xFF5E7E)]
        }
    }

    var primary: Color { gradient.first ?? CSColor.accent }

    var linearGradient: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Legendary cards earn the reactive holographic foil treatment.
    var isFoil: Bool { self == .leggendaria || self == .epica }

    var glowStrength: Double {
        switch self {
        case .comune: return 0.0
        case .rara: return 0.25
        case .epica: return 0.45
        case .leggendaria: return 0.7
        }
    }

    var symbol: String {
        switch self {
        case .comune: return "circle.grid.2x2"
        case .rara: return "diamond"
        case .epica: return "hexagon"
        case .leggendaria: return "crown"
        }
    }
}
