import SwiftUI

/// Pagina 0 · benvenuto: cos'è CarSpot e cosa farai, prima dei passi di setup.
struct ProfileSetupWelcomeStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Item: Identifiable {
        let icon: String
        let title: String
        let caption: String
        let rarity: Rarity
        var id: String { title }
    }

    private static let items: [Item] = [
        Item(icon: "camera.viewfinder", title: "Fotografa",
             caption: "Inquadra un'auto: la riconosciamo e sfochiamo targhe e volti sul telefono.",
             rarity: .comune),
        Item(icon: "rectangle.stack.fill", title: "Colleziona",
             caption: "Ogni auto diventa una carta con la sua rarità, da Comune a Leggendaria.",
             rarity: .rara),
        Item(icon: "map.fill", title: "Conquista la zona",
             caption: "Sfide del giorno, punti esperienza e classifiche del tuo quartiere.",
             rarity: .leggendaria)
    ]

    var body: some View {
        ProfileSetupPage(
            eyebrow: "BENVENUTO SU CARSPOT",
            title: "Le auto che incroci diventano carte",
            subtitle: "Ogni avvistamento è un pezzo della tua collezione. Ecco come funziona."
        ) {
            GlassPanel(cornerRadius: CSRadius.lg) {
                VStack(alignment: .leading, spacing: CSSpace.lg) {
                    ForEach(Array(Self.items.enumerated()), id: \.element.id) { index, item in
                        row(item)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : CSSpace.md)
                            .animation(
                                .easeOut(duration: 0.35).delay(Double(index) * 0.06),
                                value: appeared
                            )
                    }
                }
            }
        }
        // Solo alla prima apparizione: tornando indietro dal passo nome le righe restano.
        .onAppear { appeared = true }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: CSSpace.md) {
            Image(systemName: item.icon)
                .font(CSFont.title(18))
                .foregroundStyle(item.rarity.primary)
                .frame(width: CSSize.minTap, height: CSSize.minTap)
                .background(item.rarity.primary.opacity(0.16), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                Text(item.title)
                    .font(CSFont.title(18))
                    .foregroundStyle(CSColor.ink)
                Text(item.caption)
                    .font(CSFont.body(14))
                    .foregroundStyle(CSColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: CSSize.minTap)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        CSColor.base.ignoresSafeArea()
        ProfileSetupWelcomeStep()
    }
    .preferredColorScheme(.dark)
}
