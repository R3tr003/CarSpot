import SwiftUI

/// Spacing scale and corner radii — a single source of rhythm.
enum CSSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 36
    static let xxl: CGFloat = 56
}

enum CSRadius {
    static let sm: CGFloat = 14
    static let md: CGFloat = 22
    static let lg: CGFloat = 30
    static let card: CGFloat = 28
    /// Superfici di contenuto (`Surface`); gli elementi annidati scendono (10, 8).
    static let surface: CGFloat = 20
    static let pill: CGFloat = 999
}

/// Dimensioni minime d'interazione.
enum CSSize {
    /// Area tattile minima (HIG).
    static let minTap: CGFloat = 44
    /// Spazio occupato in basso dalla tab bar flottante del pannello.
    static let tabBarHeight: CGFloat = 100
    /// Margine in fondo ai contenuti delle tab: l'ultima riga resta sopra la tab bar.
    static let tabBarClearance: CGFloat = 130
    /// Puntino di stato (da riscattare, novità) accanto a un'etichetta.
    static let statusDot: CGFloat = 7
}
