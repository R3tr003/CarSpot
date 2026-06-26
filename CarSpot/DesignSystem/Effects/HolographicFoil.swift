import SwiftUI

/// Reactive holographic foil. An angular rainbow sweep plus a moving specular
/// band that track device tilt — the memorable moment for legendary cards.
struct HolographicFoil: View {
    var roll: Double
    var pitch: Double
    var strength: Double = 1

    var body: some View {
        ZStack {
            // Angular spectral sheen, rotated by tilt.
            AngularGradient(
                colors: [
                    Color(hex: 0xFF5E7E), Color(hex: 0xFFE176),
                    Color(hex: 0x36E2FF), Color(hex: 0xC04BFF),
                    Color(hex: 0x5CFFC8), Color(hex: 0xFF5E7E)
                ],
                center: .center,
                angle: .degrees(roll * 90)
            )
            .blendMode(.colorDodge)
            .opacity(0.35 * strength)

            // Diagonal glare band that slides across as you tilt.
            LinearGradient(
                colors: [.clear, .white.opacity(0.55 * strength), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .offset(x: roll * 120, y: pitch * 120)
            .blendMode(.overlay)
            .blur(radius: 6)
        }
        .allowsHitTesting(false)
    }
}
