import SwiftUI

/// A labelled 0...100 stat with an animated fill. Used on card detail and duels.
struct StatBar: View {
    var label: LocalizedStringKey
    var value: Int
    var tint: Color
    var animate: Bool = true
    /// Sostituisce il numero mostrato (es. "34%"); la barra usa sempre `value`.
    var valueText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: CGFloat = 0

    private var clamped: Int { min(max(value, 0), 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: CSSpace.xs) {
            HStack {
                Text(label).eyebrow()
                Spacer()
                Text(valueText ?? "\(clamped)")
                    .font(CSFont.numeric(15))
                    .foregroundStyle(CSColor.ink)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: value)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    // Riempimento piatto, senza alone.
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * shown)
                }
            }
            .frame(height: 6)
        }
        // Alla comparsa è già piena: si anima solo quando il valore cambia davvero.
        .onAppear { update(animated: false) }
        .onChange(of: value) { update(animated: animate) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(clamped) su 100")
    }

    private func update(animated: Bool) {
        let target = CGFloat(clamped) / 100
        if animated && !reduceMotion {
            withAnimation(.spring(duration: 0.6, bounce: 0)) { shown = target }
        } else {
            shown = target
        }
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        VStack(spacing: 18) {
            StatBar(label: "Potenza", value: 88, tint: Rarity.leggendaria.primary)
            StatBar(label: "Agilità", value: 64, tint: Rarity.rara.primary)
            StatBar(label: "Presenza", value: 96, tint: Rarity.epica.primary, valueText: "96%")
        }.padding()
    }
}
