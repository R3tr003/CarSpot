import SwiftUI
import SwiftData
import ImageIO

/// Contenuto del pannello quando si tocca un segnaposto: la carta (una) o l'elenco delle
/// carte di un gruppo. Sta SOPRA la `TabView` dentro lo stesso pannello di sistema, come
/// la scheda di un luogo in Mappe; la X lo chiude e torna alle tab.
/// Il dettaglio carta è `CardDetailView` così com'è, spinto in un `NavigationStack` proprio.
struct MapSpotPanel: View {
    let ids: [UUID]
    var onClose: () -> Void
    /// Aprendo il dettaglio il guscio può alzare il pannello.
    var onOpenDetail: () -> Void

    @Query private var cards: [StoredCard]
    @State private var path: [UUID] = []
    @AccessibilityFocusState private var titleFocused: Bool
    // Misure che seguono la dimensione del testo (Dynamic Type).
    @ScaledMetric(relativeTo: .body) private var heroPhotoHeight = Metrics.heroPhotoHeight
    @ScaledMetric(relativeTo: .body) private var thumbnailSide = Metrics.thumbnailSide
    @ScaledMetric(relativeTo: .caption) private var rarityDot = Metrics.rarityDot

    init(ids: [UUID], onClose: @escaping () -> Void, onOpenDetail: @escaping () -> Void) {
        self.ids = ids
        self.onClose = onClose
        self.onOpenDetail = onOpenDetail
        _cards = Query(FetchDescriptor<StoredCard>(
            predicate: #Predicate { ids.contains($0.id) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { id in
                    if let card = cards.first(where: { $0.id == id }) {
                        CardDetailView(card: card.asSpotCard)
                    }
                }
        }
        .background(CSColor.panel)
        // Il pannello copre la tab bar: VoiceOver non deve leggere ciò che sta sotto.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onChange(of: path) { old, new in
            if old.isEmpty, !new.isEmpty { onOpenDetail() }
        }
        // Carta cancellata mentre il pannello è aperto: non resta un pannello vuoto.
        .onChange(of: cards.isEmpty) { _, empty in
            if empty { onClose() }
        }
        .task { titleFocused = true }
    }

    // MARK: Contenuto

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                header
                if cards.count == 1, let card = cards.first {
                    single(card)
                } else {
                    list
                }
            }
            .padding(.horizontal, CSSpace.lg)
            .padding(.top, CSSpace.lg)
            .padding(.bottom, CSSpace.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center) {
            // Due `Text` distinti: un ternario di letterali diventerebbe una `String` non localizzata.
            Group {
                if cards.count > 1 { Text("Qui hai catturato") } else { Text("Avvistamento") }
            }
            .eyebrow()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(CSFont.title(15))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: CSSize.minTap, height: CSSize.minTap)
                    .glassEffect(.regular, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(CSPressStyle())
            .accessibilityLabel("Chiudi")
        }
    }

    // MARK: Una carta

    private func single(_ card: StoredCard) -> some View {
        Surface(.hero) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                SpotPhoto(photo: card.photo, color: card.rarity.color,
                          side: nil, radius: CSRadius.sm)
                    .frame(height: heroPhotoHeight)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    Text(card.make)
                        .font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                        .lineLimit(1)
                    Text(card.model)
                        .font(CSFont.title(22)).foregroundStyle(CSColor.ink)
                        .lineLimit(2)
                }

                HStack(spacing: CSSpace.sm) {
                    RarityBadge(rarity: card.rarity)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: CSSpace.xs) {
                    if !card.spottedArea.isEmpty {
                        Label(card.spottedArea, systemImage: "mappin.and.ellipse")
                    }
                    Label(Self.dateText(card.capturedAt), systemImage: "clock")
                }
                .font(CSFont.body(15))
                .foregroundStyle(CSColor.inkSecondary)

                PrimaryButton(title: "Apri la carta", icon: "rectangle.portrait.on.rectangle.portrait") {
                    path.append(card.id)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Un gruppo

    private var list: some View {
        Surface(.group, padding: nil) {
            // Pigro: un gruppo grande non crea tutte le righe (e le decodifiche) in una volta.
            LazyVStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { SurfaceDivider(inset: CSSpace.md + thumbnailSide + CSSpace.sm) }
                    NavigationLink(value: card.id) {
                        row(card)
                    }
                    .buttonStyle(SpotRowStyle())
                }
            }
        }
    }

    private func row(_ card: StoredCard) -> some View {
        HStack(spacing: CSSpace.sm) {
            SpotPhoto(photo: card.photo, color: card.rarity.color, side: thumbnailSide, radius: CSRadius.sm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                Text(card.make)
                    .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                    .lineLimit(1)
                Text(card.model)
                    .font(CSFont.title(15)).foregroundStyle(CSColor.ink)
                    .lineLimit(1)
                Text(Self.dateText(card.capturedAt))
                    .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: CSSpace.xs)
            HStack(spacing: CSSpace.xs) {
                Circle().fill(card.rarity.color).frame(width: rarityDot, height: rarityDot)
                Text(card.rarity.displayName)
                    .font(CSFont.caption(12).weight(.bold))
                    .foregroundStyle(card.rarity.color)
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, CSSpace.md)
        .padding(.vertical, CSSpace.sm)
        .frame(maxWidth: .infinity, minHeight: CSSize.minTap, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.make) \(card.model), rarità \(card.rarity.localizedName), \(Self.dateText(card.capturedAt))")
        .accessibilityHint("Apre la carta")
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(.app))
    }
}

// MARK: - Foto

/// Misure di base (prima dello scalamento col testo) e decodifica delle foto.
private enum Metrics {
    static let heroPhotoHeight: CGFloat = 170
    static let thumbnailSide: CGFloat = 52
    static let rarityDot: CGFloat = 7
    /// Bordo interno del colore della rarità attorno alla foto.
    static let photoBorder: CGFloat = 2
    /// Lati lunghi delle foto decodificate: hero a tutta larghezza / miniatura (52 pt a 3x).
    static let heroPixels = 900
    static let thumbnailPixels = 160
}

/// Foto della cattura (già anonimizzata) con bordo interno del colore della rarità.
/// `side == nil`: riempie la larghezza disponibile.
private struct SpotPhoto: View {
    let photo: Data?
    let color: Color
    let side: CGFloat?
    let radius: CGFloat

    @State private var image: SpotDecodedImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Color.clear
            .frame(width: side, height: side)
            .frame(maxWidth: side == nil ? .infinity : nil)
            .background(CSColor.nested)
            .overlay {
                if let image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "car.fill")
                        .font(CSFont.title(side == nil ? 40 : 17))
                        .foregroundStyle(CSColor.inkTertiary)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(color, lineWidth: Metrics.photoBorder) }
            .task(id: photo?.count) {
                guard let photo else { image = nil; return }
                image = await decodeSpotPhoto(photo, maxPixel: side == nil ? Metrics.heroPixels : Metrics.thumbnailPixels)
            }
    }
}

/// Immagine già decodificata, passabile tra isolation.
private struct SpotDecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Decodifica ImageIO fuori dal main actor (orientamento applicato).
@concurrent
private func decodeSpotPhoto(_ data: Data, maxPixel: Int) async -> SpotDecodedImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return SpotDecodedImage(cgImage: cg)
}

/// Pressione di una riga: stessa resa di `CSPressStyle`, con fondo che si accende.
private struct SpotRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(pressed ? CSColor.nested : .clear)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: pressed)
    }
}
