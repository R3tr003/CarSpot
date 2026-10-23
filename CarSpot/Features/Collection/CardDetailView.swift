import SwiftUI

struct CardDetailView: View {
    let card: SpotCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = MotionManager()

    // Con Reduce Motion la carta resta ferma (niente foil reattivo né inclinazione).
    private var roll: Double { reduceMotion ? 0 : motion.roll }
    private var pitch: Double { reduceMotion ? 0 : motion.pitch }

    private var infoRows: [(label: LocalizedStringKey, value: String, icon: String)] {
        [("Zona", card.spottedArea, "mappin.and.ellipse"),
         ("Quando", relativeDay(card.spottedDaysAgo), "clock"),
         ("Colore", card.colorName, "paintpalette")]
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            AsphaltBackground(tint: card.rarity.primary, intensity: 1.4)

            ScrollView {
                VStack(spacing: CSSpace.xl) {
                    SpotCardView(card: card, roll: roll, pitch: pitch)
                        .frame(maxWidth: 280)
                        .rotation3DEffect(.degrees(roll * 6),
                                          axis: (x: 0, y: 1, z: 0))
                        .rotation3DEffect(.degrees(-pitch * 6),
                                          axis: (x: 1, y: 0, z: 0))
                        .padding(.top, CSSpace.lg)

                    // Nome completo: nella carta può essere troncato.
                    VStack(spacing: CSSpace.sm) {
                        Text(card.title)
                            .font(CSFont.title(22)).foregroundStyle(CSColor.ink)
                            .multilineTextAlignment(.center)
                        RarityBadge(rarity: card.rarity)
                    }
                    .frame(maxWidth: .infinity)

                    if card.rarity.isFoil && !reduceMotion {
                        Label("Inclina il telefono per vedere il foil",
                              systemImage: "hand.draw.fill")
                            .font(CSFont.caption(12))
                            .foregroundStyle(CSColor.inkSecondary)
                    }

                    GlassPanel {
                        VStack(alignment: .leading, spacing: CSSpace.lg) {
                            Text("Scheda tecnica").eyebrow(card.rarity.primary)
                            StatBar(label: "Potenza", value: card.power, tint: card.rarity.primary)
                            StatBar(label: "Agilità", value: card.agility, tint: card.rarity.primary)
                            StatBar(label: "Presenza", value: card.presence, tint: card.rarity.primary)
                        }
                    }

                    GlassPanel {
                        VStack(alignment: .leading, spacing: CSSpace.md) {
                            Text("Avvistamento").eyebrow(card.rarity.primary)
                            let rows = infoRows
                            ForEach(rows.indices, id: \.self) { i in
                                if i > 0 { Divider().overlay(CSColor.hairline) }
                                infoRow(rows[i].label, rows[i].value, rows[i].icon)
                            }
                        }
                    }
                }
                .padding(CSSpace.lg)
                .padding(.bottom, CSSpace.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(card.title)
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            if !reduceMotion { motion.start() }
            // Nome del case (es. "epica"), stabile e indipendente dalla lingua.
            AppServices.errors.metric(count: "card.view", attributes: ["rarity": .string(String(describing: card.rarity))])
            AppServices.analytics.track(.cardViewed(rarity: String(describing: card.rarity)))
        }
        .onDisappear { motion.stop() }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String, _ icon: String) -> some View {
        // Con Dynamic Type molto grande etichetta e valore vanno in colonna.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                infoLabel(label, icon)
                Spacer(minLength: CSSpace.md)
                infoValue(value, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                infoLabel(label, icon)
                infoValue(value, alignment: .leading)
            }
        }
    }

    private func infoLabel(_ label: LocalizedStringKey, _ icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
    }

    private func infoValue(_ value: String, alignment: TextAlignment) -> some View {
        Text(value)
            .font(CSFont.body(15)).foregroundStyle(CSColor.ink)
            .multilineTextAlignment(alignment)
    }

    private func relativeDay(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "Oggi")
        case 1: return String(localized: "Ieri")
        default:
            // "12 giorni fa", "2 mesi fa", "1 anno fa" nella lingua dell'app.
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = .app
            formatter.unitsStyle = .full
            let date = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
            return formatter.localizedString(for: date, relativeTo: .now)
        }
    }
}

#Preview {
    NavigationStack {
        CardDetailView(card: SpotCard.sample[0])
    }
    .preferredColorScheme(.dark)
}
