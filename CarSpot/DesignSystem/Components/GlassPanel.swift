import SwiftUI

/// Contenitore Liquid Glass riusabile: solo `.glassEffect` nativo, neutro.
/// Il bordo speculare lo disegna già il materiale di sistema; niente riempimenti
/// colorati: il colore pieno su blocchi generici sembra un template.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = CSRadius.card
    /// Ignorato di proposito (vetro sempre neutro); resta per compatibilità.
    var tint: Color? = nil
    var padding: CGFloat = CSSpace.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
