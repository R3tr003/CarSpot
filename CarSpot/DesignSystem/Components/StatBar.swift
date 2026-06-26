import SwiftUI

/// A labelled 0...100 stat with an animated fill. Used on card detail and duels.
struct StatBar: View {
    var label: String
    var value: Int
    var tint: Color
    var animate: Bool = true

    @State private var shown: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).eyebrow()
                Spacer()
                Text("\(value)")
                    .font(CSFont.numeric(15))
                    .foregroundStyle(CSColor.ink)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [tint.opacity(0.7), tint],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * shown)
                        .shadow(color: tint.opacity(0.5), radius: 6, y: 0)
                }
            }
            .frame(height: 8)
        }
        .onAppear {
            let target = CGFloat(value) / 100
            if animate {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.05)) {
                    shown = target
                }
            } else {
                shown = target
            }
        }
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        VStack(spacing: 18) {
            StatBar(label: "Potenza", value: 88, tint: Rarity.leggendaria.primary)
            StatBar(label: "Agilità", value: 64, tint: Rarity.rara.primary)
            StatBar(label: "Presenza", value: 96, tint: Rarity.epica.primary)
        }.padding()
    }
}
