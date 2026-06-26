import SwiftUI

/// A reusable Liquid Glass container. Wraps native `.glassEffect` and adds the
/// specular hairline + inner shadow that gives the material physical depth.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = CSRadius.card
    var tint: Color? = nil
    var padding: CGFloat = CSSpace.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(.clear)
                        .glassEffect(glass, in: shape)
                    // Top specular highlight.
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [CSColor.specular, .clear, CSColor.hairline],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
    }

    private var glass: Glass {
        if let tint {
            return .regular.tint(tint.opacity(0.5))
        }
        return .regular
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Liquid Glass").eyebrow()
                Text("Pannello").font(CSFont.title())
                    .foregroundStyle(CSColor.ink)
            }
        }
        .padding()
    }
}
