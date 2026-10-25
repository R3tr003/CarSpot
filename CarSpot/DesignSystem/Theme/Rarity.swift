import SwiftUI

/// Rarity is the spine of the visual system: the accent colour of any card,
/// badge or glow is derived from its rarity.
/// Materiale della carta per rarità: opaca, bordo metallico, bordo foil, foil intero.
enum RarityFinish: Sendable {
    case matte, metalEdge, foilEdge, fullFoil
}

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

    /// Un colore per rarità, usato ovunque (bordi, badge, pallini, riflessi). Niente arcobaleno.
    var color: Color {
        switch self {
        case .comune:      return Color(hex: 0xB4BCCB)
        case .rara:        return Color(hex: 0x36E2FF)
        case .epica:       return Color(hex: 0xC04BFF)
        case .leggendaria: return Color(hex: 0xFFC14D)
        }
    }

    /// Monocromo: resta per i chiamanti che vogliono un `[Color]`.
    var gradient: [Color] { [color] }

    var primary: Color { color }

    /// Finitura della carta: la rarità si riconosce dal materiale, non da un alone.
    var finish: RarityFinish {
        switch self {
        case .comune: .matte
        case .rara: .metalEdge
        case .epica: .foilEdge
        case .leggendaria: .fullFoil
        }
    }

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
