import SwiftUI

/// Palette "Nocturne / Asphalt Premium".
/// Dark-first, near-black warm asphalt with vivid accents reserved for rarity.
enum CSColor {

    // MARK: Surfaces (warm near-black, never pure #000)
    /// Deepest background — the asphalt at night.
    static let base = Color(hex: 0x0B0C0F)
    /// One step up, for sheets and grouped sections.
    static let surface = Color(hex: 0x14161B)
    /// Raised material seen through glass.
    static let elevated = Color(hex: 0x1C1F26)

    // MARK: Ink
    static let ink = Color(hex: 0xF4F6FB)
    static let inkSecondary = Color(hex: 0xA7AEBC)
    static let inkTertiary = Color(hex: 0x6A7180)

    // MARK: Brand accent — electric "spotting" cyan-green
    static let accent = Color(hex: 0x1CD5F3)
    static let accentWarm = Color(hex: 0xFFB23E)

    // MARK: Hairlines & strokes
    static let hairline = Color.white.opacity(0.08)
    static let specular = Color.white.opacity(0.35)

    // MARK: Atmospheric gradient washes for backgrounds
    static let glowTop = Color(hex: 0x16323A)
    static let glowBottom = Color(hex: 0x0B0C0F)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
