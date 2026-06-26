import SwiftUI

struct CardDetailView: View {
    let card: SpotCard
    @State private var motion = MotionManager()

    var body: some View {
        ZStack {
            AsphaltBackground(tint: card.rarity.primary, intensity: 1.4)

            ScrollView {
                VStack(spacing: CSSpace.xl) {
                    SpotCardView(card: card, roll: motion.roll, pitch: motion.pitch)
                        .frame(maxWidth: 280)
                        .rotation3DEffect(.degrees(motion.roll * 6),
                                          axis: (x: 0, y: 1, z: 0))
                        .rotation3DEffect(.degrees(-motion.pitch * 6),
                                          axis: (x: 1, y: 0, z: 0))
                        .padding(.top, CSSpace.lg)

                    if card.rarity.isFoil {
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
                            infoRow("Zona", card.spottedArea, "mappin.and.ellipse")
                            Divider().overlay(CSColor.hairline)
                            infoRow("Quando", relativeDay(card.spottedDaysAgo), "clock")
                            Divider().overlay(CSColor.hairline)
                            infoRow("Colore", card.colorName, "paintpalette")
                        }
                    }
                }
                .padding(CSSpace.lg)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(card.title)
        .toolbarTitleDisplayMode(.inline)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func infoRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
            Spacer()
            Text(value).font(CSFont.body(15)).foregroundStyle(CSColor.ink)
        }
    }

    private func relativeDay(_ days: Int) -> String {
        switch days {
        case 0: return "Oggi"
        case 1: return "Ieri"
        default: return "\(days) giorni fa"
        }
    }
}

#Preview {
    NavigationStack {
        CardDetailView(card: SpotCard.sample[0])
    }
    .preferredColorScheme(.dark)
}
