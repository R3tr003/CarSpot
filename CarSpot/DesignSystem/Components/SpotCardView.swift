import SwiftUI

/// The collectible card. Renders the vehicle, rarity framing and — for foil
/// rarities — the motion-reactive holographic sheen.
struct SpotCardView: View {
    let card: SpotCard
    var roll: Double = 0
    var pitch: Double = 0
    var showStats: Bool = false

    var body: some View {
        ZStack {
            // Rarity-tinted base with a vignette so the subject pops.
            RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CSColor.elevated, CSColor.surface],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
                .fill(card.rarity.linearGradient)
                .opacity(0.16)

            // Subject.
            VStack(spacing: CSSpace.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.make.uppercased()).eyebrow(card.rarity.primary)
                        Text(card.model)
                            .font(CSFont.title(19))
                            .foregroundStyle(CSColor.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer()
                    RarityBadge(rarity: card.rarity, compact: true)
                }

                Spacer()

                Group {
                    if let data = card.imageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous))
                    } else {
                        Image(systemName: card.symbol)
                            .font(.system(size: 56, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(colors: card.rarity.gradient,
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .shadow(color: card.rarity.primary.opacity(card.rarity.glowStrength),
                                    radius: 16)
                    }
                }
                .offset(x: roll * 8, y: pitch * 6) // parallax

                Spacer()

                HStack {
                    Label("\(card.year)", systemImage: "calendar")
                    Spacer()
                    Label(card.colorName, systemImage: "paintpalette.fill")
                        .lineLimit(1)
                }
                .font(CSFont.caption(12))
                .foregroundStyle(CSColor.inkSecondary)

                if showStats {
                    HStack(spacing: 6) {
                        miniStat("PWR", card.power)
                        miniStat("AGL", card.agility)
                        miniStat("PRS", card.presence)
                    }
                }
            }
            .padding(CSSpace.md)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .overlay {
            if card.rarity.isFoil {
                HolographicFoil(roll: roll, pitch: pitch, strength: card.rarity.glowStrength)
                    .clipShape(RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
                .strokeBorder(card.rarity.linearGradient, lineWidth: 1.5)
                .opacity(0.8)
        }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 14)
        .shadow(color: card.rarity.primary.opacity(card.rarity.glowStrength * 0.5), radius: 24, y: 0)
    }

    private func miniStat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(CSFont.numeric(15)).foregroundStyle(CSColor.ink)
            Text(label).font(.system(size: 8, weight: .bold)).tracking(1)
                .foregroundStyle(CSColor.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        SpotCardView(card: SpotCard.sample[0], showStats: true)
            .frame(width: 240)
    }
}
