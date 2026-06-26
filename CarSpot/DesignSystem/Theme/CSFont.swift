import SwiftUI

/// Typography. SF Pro Rounded carries the "game" tone for numbers and titles;
/// a tight, wide-tracked condensed treatment is used for eyebrow labels.
enum CSFont {

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func numeric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

extension View {
    /// Wide-tracked uppercase eyebrow label used throughout the UI.
    func eyebrow(_ color: Color = CSColor.inkTertiary) -> some View {
        self
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
