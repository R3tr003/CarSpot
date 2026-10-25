import SwiftUI

/// Superficie opaca "a gradini" per i blocchi di contenuto. La profondità viene dal
/// tono (più chiaro = più in alto) e da un filo di luce sul bordo superiore, non dal
/// vetro: il Liquid Glass resta su tab bar e controlli flottanti.
/// - `hero`: il blocco che risponde alla domanda della schermata (uno per schermata).
/// - `group`: righe raggruppate con `SurfaceDivider`, statistiche, liste.
struct Surface<Content: View>: View {
    enum Level { case hero, group }

    private let level: Level
    private let padding: CGFloat?
    private let content: Content

    init(_ level: Level = .group, padding: CGFloat? = CSSpace.md, @ViewBuilder content: () -> Content) {
        self.level = level
        self.padding = padding
        self.content = content()
    }

    private var fill: Color { level == .hero ? CSColor.hero : CSColor.group }
    private var edgeLight: Double { level == .hero ? 0.09 : 0.06 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: CSRadius.surface, style: .continuous) }

    var body: some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            // Luce dall'alto: solo il bordo superiore, che sfuma verso i lati.
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(edgeLight), .clear],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(level == .hero ? 0.35 : 0), radius: 24, y: 10)
    }
}

/// Divisore 1 pt tra righe di un `Surface(.group)`.
struct SurfaceDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CSColor.divider)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Fila di numeri senza riquadri singoli: etichetta sopra, valore sotto, divisori
/// verticali, cifre tabulari.
struct KPIStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: LocalizedStringKey
        let value: String
        /// Etichetta per VoiceOver quando `label` è un'abbreviazione (es. "PE").
        let spoken: LocalizedStringKey?

        init(_ label: LocalizedStringKey, value: String, spoken: LocalizedStringKey? = nil) {
            self.label = label
            self.value = value
            self.spoken = spoken
        }
    }

    private let items: [Item]

    init(_ items: [Item]) { self.items = items }

    var body: some View {
        Surface(.group, padding: nil) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    if item.id != items.first?.id {
                        Rectangle().fill(CSColor.divider).frame(width: 1).padding(.vertical, CSSpace.sm)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: CSSpace.xxs) {
                        Text(item.label).eyebrow()
                        Text(item.value)
                            .font(CSFont.numeric(22))
                            .monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CSSpace.md)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken ?? item.label)
                    .accessibilityValue(item.value)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: CSSpace.md) {
            Surface(.hero) {
                Text("Livello 1").font(CSFont.title(22)).foregroundStyle(CSColor.ink)
            }
            Surface(.group, padding: nil) {
                VStack(spacing: 0) {
                    Text("Riga uno").padding(CSSpace.md).frame(maxWidth: .infinity, alignment: .leading)
                    SurfaceDivider(inset: CSSpace.md)
                    Text("Riga due").padding(CSSpace.md).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(CSColor.ink)
            }
            KPIStrip([.init("Carte", value: "13"), .init("Modelli", value: "9"), .init("XP", value: "380")])
        }
        .padding()
    }
    .background(CSColor.panel)
    .preferredColorScheme(.dark)
}
