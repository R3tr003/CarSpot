import SwiftUI
import ImageIO

/// The collectible card. La rarità si legge dal materiale (opaca, bordo metallico,
/// bordo foil, foil intero) e dal suo colore unico, mai da un alone. Il riflesso
/// speculare e il foil seguono l'inclinazione.
/// `compact` = versione per la griglia della collezione: solo bordo, niente foil né riflessi.
struct SpotCardView: View {
    let card: SpotCard
    var roll: Double = 0
    var pitch: Double = 0
    var showStats: Bool = false
    var compact: Bool = false
    /// Copie di questo modello in collezione: "×N" sulla carta quando > 1.
    var copies: Int = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
    }
    private var color: Color { card.rarity.color }
    /// Inclinazione effettiva: ferma con Riduci movimento e nella versione compatta.
    private var tiltRoll: Double { reduceMotion || compact ? 0 : roll }
    private var tiltPitch: Double { reduceMotion || compact ? 0 : pitch }

    var body: some View {
        ZStack {
            shape.fill(
                LinearGradient(colors: [CSColor.hero, CSColor.group],
                               startPoint: .top, endPoint: .bottom)
            )

            // Subject.
            VStack(spacing: CSSpace.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: CSSpace.xxs) {
                        Text(card.make).eyebrow(color)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(card.model)
                            .font(CSFont.title(19))
                            .foregroundStyle(CSColor.ink)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: CSSpace.xs)
                    if copies > 1 { copiesPill }
                }

                Spacer(minLength: 0)

                // Parallasse: disattivato con Reduce Motion.
                CardPhoto(imageData: card.imageData, symbol: card.symbol, color: color)
                    .offset(x: tiltRoll * 8, y: tiltPitch * 6)

                Spacer(minLength: 0)

                VStack(spacing: CSSpace.xs) {
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

                    SurfaceDivider()
                    HStack {
                        RarityBadge(rarity: card.rarity, compact: true)
                        Spacer(minLength: 0)
                    }
                }

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
            RarityFrame(rarity: card.rarity, shape: shape,
                        roll: tiltRoll, pitch: tiltPitch, compact: compact)
        }
        .shadow(color: .black.opacity(compact ? 0.3 : 0.5),
                radius: compact ? 10 : 20, y: compact ? 6 : 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(statsSpoken)
    }

    /// "×N" in alto a destra.
    private var copiesPill: some View {
        Text("×\(copies)")
            .font(CSFont.micro)
            .monospacedDigit()
            .foregroundStyle(CSColor.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(CSColor.nested))
            .accessibilityHidden(true)
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
        if copies > 1 { parts.append(String(localized: "\(copies) copie")) }
        return parts.joined(separator: ", ")
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(CSFont.numeric(15)).foregroundStyle(CSColor.ink)
            Text(label).font(CSFont.micro)
                .foregroundStyle(CSColor.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.xs)
        .background(RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous).fill(CSColor.nested))
    }
}

// MARK: - Bordo e materiale per rarità

/// Bordo, foil e riflesso di una carta, per rarità. Si usa come `overlay` di una carta
/// con la stessa `shape`. `roll`/`pitch` sono già l'inclinazione effettiva (0 con
/// Riduci movimento); `compact` = solo bordo, niente foil né riflessi.
struct RarityFrame: View {
    let rarity: Rarity
    let shape: RoundedRectangle
    var roll: Double = 0
    var pitch: Double = 0
    var compact: Bool = false

    private var color: Color { rarity.color }
    private var finish: RarityFinish { rarity.finish }

    var body: some View {
        ZStack {
            foilLayer
            specularLayer
            borderLayer
        }
        .allowsHitTesting(false)
    }

    /// Foil monocromo: sul bordo (Epica) o su tutta la carta (Leggendaria). Mai in compact.
    @ViewBuilder private var foilLayer: some View {
        if !compact {
            switch finish {
            case .fullFoil:
                HolographicFoil(color: color, roll: roll, pitch: pitch, strength: 1, wash: 0.09)
                    .clipShape(shape)
            case .foilEdge:
                HolographicFoil(color: color, roll: roll, pitch: pitch, strength: 1.6)
                    .mask { shape.strokeBorder(lineWidth: 5) }
            case .matte, .metalEdge:
                EmptyView()
            }
        }
    }

    /// Riflesso speculare radiale tinto del colore della rarità, che segue l'inclinazione.
    @ViewBuilder private var specularLayer: some View {
        if !compact {
            GeometryReader { geo in
                let base: Double = switch finish {
                case .matte: 0.10
                case .metalEdge: 0.20
                case .foilEdge: 0.24
                case .fullFoil: 0.30
                }
                let level = base * (0.4 + min(1, (abs(roll) + abs(pitch)) / 0.8))
                RadialGradient(
                    colors: [color.opacity(level), .clear],
                    center: UnitPoint(x: 0.5 + roll * 0.35, y: 0.2 - pitch * 0.25),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.55
                )
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }

    /// Bordo: 1 pt tenue (opaca), 2 pt metallico con luce legata a `roll` (Rara, Leggendaria),
    /// 2 pt pieno sotto il foil (Epica).
    @ViewBuilder private var borderLayer: some View {
        switch finish {
        case .matte:
            shape.strokeBorder(color.opacity(0.35), lineWidth: 1)
        case .foilEdge:
            shape.strokeBorder(color, lineWidth: 2)
        case .metalEdge, .fullFoil:
            if compact {
                shape.strokeBorder(color, lineWidth: 2)
            } else {
                let highlight = min(0.9, max(0.1, 0.5 + roll * 0.4))
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: color.mix(with: .black, by: 0.18), location: 0),
                            .init(color: color.mix(with: .white, by: 0.5), location: highlight),
                            .init(color: color.mix(with: .black, by: 0.18), location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            }
        }
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
    let color: Color

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
                        .foregroundStyle(color)
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
        CSColor.panel.ignoresSafeArea()
        SpotCardView(card: SpotCard.sample[0], roll: 0.4, showStats: true, copies: 3)
            .frame(width: 240)
    }
}
