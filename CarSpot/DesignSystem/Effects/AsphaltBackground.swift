import SwiftUI

/// The app-wide atmosphere: a warm near-black base with a soft directional glow
/// and a fine grain overlay so surfaces never read as flat fields of colour.
struct AsphaltBackground: View {
    var tint: Color = CSColor.accent
    var intensity: Double = 1

    var body: some View {
        ZStack {
            CSColor.base

            // Top-corner aurora wash.
            RadialGradient(
                colors: [tint.opacity(0.22 * intensity), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 520
            )

            // Low warm counter-glow grounds the composition.
            RadialGradient(
                colors: [CSColor.accentWarm.opacity(0.10 * intensity), .clear],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 480
            )

            GrainOverlay(opacity: 0.05)
        }
        .ignoresSafeArea()
    }
}

/// Procedural film grain rendered with Canvas — adds tactile texture cheaply.
struct GrainOverlay: View {
    var opacity: Double = 0.06

    var body: some View {
        Canvas { context, size in
            var generator = SystemRandomNumberGenerator()
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = Double.random(in: 0...size.width, using: &generator)
                let y = Double.random(in: 0...size.height, using: &generator)
                let s = Double.random(in: 0.4...1.1, using: &generator)
                let rect = CGRect(x: x, y: y, width: s, height: s)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.5)))
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

#Preview {
    AsphaltBackground()
}
