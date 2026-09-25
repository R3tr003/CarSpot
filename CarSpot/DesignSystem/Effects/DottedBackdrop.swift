import SwiftUI

/// Animated dotted-grid backdrop (Flighty-style) — a soft light sweeps across a
/// field of dots. Used behind the login and onboarding screens.
struct DottedBackdrop: View {
    var tint: Color = CSColor.accent
    var spacing: CGFloat = 26

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cx = size.width * 0.5 + cos(t * 0.45) * size.width * 0.28
                let cy = size.height * 0.42 + sin(t * 0.6) * size.height * 0.18

                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = CGFloat(c) * spacing
                        let y = CGFloat(r) * spacing
                        let d = hypot(x - cx, y - cy)
                        let glow = max(0, 1 - d / 320)
                        let radius = 0.9 + glow * 1.8
                        let opacity = 0.05 + glow * 0.55
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack { CSColor.base; DottedBackdrop() }.ignoresSafeArea()
}
