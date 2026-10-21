import SwiftUI
import ImageIO

/// The collectible card. Renders the vehicle, rarity framing and — for foil
/// rarities — the motion-reactive holographic sheen.
/// `compact` = versione per la griglia della collezione: niente foil né glow.
struct SpotCardView: View {
    let card: SpotCard
    var roll: Double = 0
    var pitch: Double = 0
    var showStats: Bool = false
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    VStack(alignment: .leading, spacing: CSSpace.xxs) {
                        Text(card.make.uppercased()).eyebrow(card.rarity.primary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(card.model)
                            .font(CSFont.title(19))
                            .foregroundStyle(CSColor.ink)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: CSSpace.xs)
                    RarityBadge(rarity: card.rarity, compact: true)
                }

                Spacer(minLength: 0)

                // Parallasse: disattivato con Reduce Motion.
                CardPhoto(imageData: card.imageData, symbol: card.symbol, rarity: card.rarity)
                    .offset(x: reduceMotion ? 0 : roll * 8, y: reduceMotion ? 0 : pitch * 6)

                Spacer(minLength: 0)

                HStack {
                    if card.year > 0 {
                        Label(String(card.year), systemImage: "calendar")
                        Spacer(minLength: CSSpace.xs)
                    }
                    Label(card.colorName, systemImage: "paintpalette.fill")
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(CSFont.caption(12))
                .foregroundStyle(CSColor.inkSecondary)

                if showStats {
                    HStack(spacing: CSSpace.xs) {
                        miniStat("PWR", card.power)
                        miniStat("AGL", card.agility)
                        miniStat("PRS", card.presence)
                    }
                }
            }
            .padding(CSSpace.md)
        }
        .aspectRatio(0.7, contentMode: .fit)
        // Layout a proporzione fissa: il Dynamic Type è limitato.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .overlay {
            if card.rarity.isFoil && !compact {
                HolographicFoil(roll: roll, pitch: pitch, strength: card.rarity.glowStrength)
                    .clipShape(RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
                .strokeBorder(card.rarity.linearGradient, lineWidth: 1.5)
                .opacity(0.8)
        }
        .shadow(color: .black.opacity(compact ? 0.3 : 0.5),
                radius: compact ? 10 : 20, y: compact ? 6 : 14)
        .shadow(color: card.rarity.primary.opacity(compact ? 0 : card.rarity.glowStrength * 0.5),
                radius: compact ? 0 : 24, y: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(statsSpoken)
    }

    /// Statistiche lette a voce (vuote se la carta non le mostra).
    private var statsSpoken: String {
        guard showStats else { return "" }
        return String(localized: "Potenza \(card.power), Agilità \(card.agility), Presenza \(card.presence)")
    }

    private var accessibilityLabelText: String {
        var parts = ["\(card.make) \(card.model)"]
        if card.year > 0 { parts.append(String(card.year)) }
        parts.append(card.rarity.localizedName)
        parts.append(card.colorName)
        return parts.joined(separator: ", ")
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(CSFont.numeric(15)).foregroundStyle(CSColor.ink)
            Text(label).font(CSFont.micro).tracking(1)
                .foregroundStyle(CSColor.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.xs)
        .background(RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous).fill(.white.opacity(0.06)))
    }
}

// MARK: - Foto con miniatura decodificata una volta sola

/// Miniatura già decodificata, passabile tra isolation.
private struct DecodedThumbnail: @unchecked Sendable {
    let image: CGImage
}

/// Decodifica ImageIO fuori dal main actor (miniatura ~600 px, orientamento applicato).
@concurrent
private func decodeThumbnail(_ data: Data) async -> DecodedThumbnail? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 600
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return DecodedThumbnail(image: cg)
}

private struct CardPhoto: View {
    let imageData: Data?
    let symbol: String
    let rarity: Rarity

    @State private var thumbnail: DecodedThumbnail?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 96)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Fallback mentre decodifica o senza foto.
                    Image(systemName: symbol)
                        .font(.system(size: 56, weight: .regular))
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(
                            LinearGradient(colors: rarity.gradient,
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: rarity.primary.opacity(rarity.glowStrength), radius: 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous))
            .task(id: imageData?.count) {
                guard let data = imageData else { thumbnail = nil; return }
                thumbnail = await decodeThumbnail(data)
            }
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        SpotCardView(card: SpotCard.sample[0], showStats: true)
            .frame(width: 240)
    }
}
