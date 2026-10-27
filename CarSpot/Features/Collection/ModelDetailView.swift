import SwiftUI
import SwiftData
import ImageIO

/// Dettaglio di un modello dell'album: carta standard, versioni (trovate e da trovare),
/// le tue foto, dati e attribuzione dell'immagine. `CardDetailView` resta per la singola foto.
struct ModelDetailView: View {
    let modelId: String

    /// Tutto ciò che dipende dall'abbinamento delle carte, calcolato fuori dal `body`.
    private struct Detail {
        let rows: [AlbumVariantRow]
        let entry: AlbumModelEntry
        let photos: [StoredCard]
        let cardsByID: [UUID: StoredCard]
    }

    @Query(filter: #Predicate<StoredCard> { $0.isRepeat == false },
           sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @State private var detail: Detail?
    /// Voce della griglia di provenienza: la carta c'è già al primo frame, dopo lo zoom.
    @State private var entry: AlbumModelEntry?

    init(modelId: String, initialEntry: AlbumModelEntry? = nil) {
        self.modelId = modelId
        _entry = State(initialValue: initialEntry)
    }

    private var store: CatalogStore { CatalogStore.shared }

    /// Cambia quando cambiano le carte o il catalogo: rifà l'abbinamento fuori dal main actor.
    private var matchKey: Int {
        var hasher = Hasher()
        for card in stored {
            hasher.combine(card.id)
            hasher.combine(card.make)
            hasher.combine(card.model)
        }
        hasher.combine(store.index?.modelCount)
        return hasher.finalize()
    }

    var body: some View {
        ZStack {
            CSColor.panel.ignoresSafeArea()
            if let index = store.index, let model = index.model(id: modelId),
               let make = index.make(id: model.makeId) {
                content(index: index, model: model, make: make)
            } else {
                Text("Modello non trovato")
                    .font(CSFont.body(16)).foregroundStyle(CSColor.inkSecondary)
            }
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .task(id: matchKey) { await refresh() }
    }

    private var title: String {
        guard let index = store.index, let model = index.model(id: modelId),
              let make = index.make(id: model.makeId) else { return "" }
        return "\(make.name) \(index.displayName(of: model))"
    }

    // MARK: - Calcolo

    private func refresh() async {
        guard let index = store.index, let matcher = store.matcher,
              let model = index.model(id: modelId), let make = index.make(id: model.makeId) else { return }
        let cards = stored.map {
            OwnedCard(id: $0.id, make: $0.make, model: $0.model, year: $0.year,
                      rarity: $0.rarity, capturedAt: $0.capturedAt)
        }
        let matches = await makeAlbumMatches(cards: cards, matcher: matcher)
        guard !Task.isCancelled else { return }

        let rows = AlbumBuilder.variantRows(modelId: modelId, index: index, matches: matches)
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let photos = matches.cards(forModel: modelId).compactMap { byID[$0.id] }
        let entry = makeEntry(index: index, model: model, make: make, rows: rows)
        self.entry = entry
        detail = Detail(rows: rows, entry: entry, photos: photos, cardsByID: byID)
    }

    /// Voce della carta grande, ricavata dalle righe delle versioni.
    private func makeEntry(index: CatalogIndex, model: CatalogModel, make: CatalogMake,
                           rows: [AlbumVariantRow]) -> AlbumModelEntry {
        let variants = rows.filter { !$0.isOtherVersion }
        let found = rows.filter(\.isFound)
        let order = Rarity.allCases
        let best = found.max { (order.firstIndex(of: $0.rarity) ?? 0) < (order.firstIndex(of: $1.rarity) ?? 0) }
        let base = index.baseVariant(ofModel: modelId)
        let rarity = best?.rarity ?? base.map(index.catalogRarity(of:)) ?? .comune
        let image = variants.first { $0.isFound && $0.image != nil }?.image ?? base?.image
        return AlbumModelEntry(
            id: modelId, makeName: make.name, name: index.displayName(of: model),
            bodyType: model.bodyType, rarity: rarity, isFound: !found.isEmpty,
            copies: found.reduce(0) { $0 + $1.copies }, isNew: false,
            versionsFound: variants.filter(\.isFound).count,
            versionsTotal: index.variants(ofModel: modelId).count, image: image
        )
    }

    // MARK: - Contenuto

    private func content(index: CatalogIndex, model: CatalogModel, make: CatalogMake) -> some View {
        ScrollView {
            VStack(spacing: CSSpace.xl) {
                if let entry {
                    ModelHeroCard(entry: entry)

                    VStack(spacing: CSSpace.sm) {
                        Text("\(make.name) \(entry.name)")
                            .font(CSFont.title(22)).foregroundStyle(CSColor.ink)
                            .multilineTextAlignment(.center)
                        RarityBadge(rarity: entry.rarity)
                        if !entry.isFound {
                            Text("Non l'hai ancora trovata. Fotografala per sbloccare la carta.")
                                .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, CSSpace.xs)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let detail {
                    if !detail.rows.isEmpty {
                        versionsGroup(detail, bodyType: model.bodyType)
                    }
                    if !detail.photos.isEmpty { photosGroup(detail.photos) }
                }
                dataGroup(model: model, make: make)
                attribution(entry?.image)
            }
            .padding(CSSpace.lg)
            .padding(.bottom, CSSpace.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Versioni

    private func versionsGroup(_ detail: Detail, bodyType: BodyType) -> some View {
        Surface(.group, padding: nil) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Versioni").eyebrow()
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, CSSpace.md).padding(.top, CSSpace.md).padding(.bottom, CSSpace.xs)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(detail.rows) { row in
                        if row.id != detail.rows.first?.id { SurfaceDivider(inset: CSSpace.md) }
                        VersionRow(row: row, bodyType: bodyType,
                                   card: row.isOtherVersion ? row.cardIDs.first.flatMap { detail.cardsByID[$0] } : nil)
                    }
                }
            }
        }
    }

    // MARK: - Le tue foto

    private func photosGroup(_ photos: [StoredCard]) -> some View {
        Surface(.group) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                Text("Le tue foto").eyebrow().accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CSSpace.sm), count: 3),
                          spacing: CSSpace.sm) {
                    ForEach(photos, id: \.id) { card in
                        PhotoCell(card: card)
                    }
                }
            }
        }
    }

    // MARK: - Dati e attribuzione

    private func dataGroup(model: CatalogModel, make: CatalogMake) -> some View {
        var rows: [(label: LocalizedStringKey, value: String)] = [
            ("Carrozzeria", model.bodyType.localizedName)
        ]
        if let years = yearsText(model) { rows.append(("Anni", years)) }
        if let code = make.country, let name = Locale.app.localizedString(forRegionCode: code) {
            rows.append(("Paese", name))
        }
        return Surface(.group) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                ForEach(rows.indices, id: \.self) { i in
                    if i > 0 { SurfaceDivider() }
                    dataRow(rows[i].label, rows[i].value)
                }
            }
        }
    }

    private func dataRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        // Con Dynamic Type molto grande etichetta e valore vanno in colonna.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
                Spacer(minLength: CSSpace.md)
                Text(value).font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                Text(label).font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
                Text(value).font(CSFont.body(15)).foregroundStyle(CSColor.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "2016–2020", "dal 2012" (ancora in produzione) o nulla.
    private func yearsText(_ model: CatalogModel) -> String? {
        switch (model.yearStart, model.yearEnd) {
        case let (start?, end?) where end != start: return "\(start)–\(end)"
        case let (start?, _?): return "\(start)"
        case let (start?, nil): return String(localized: "dal \(String(start))")
        default: return nil
        }
    }

    @ViewBuilder private func attribution(_ image: CatalogImage?) -> some View {
        if let image {
            let text = attributionText(image)
            Group {
                if let url = image.sourceURL {
                    Link(destination: url) {
                        Text(text).underline()
                            .frame(maxWidth: .infinity, minHeight: CSSize.minTap, alignment: .leading)
                            .contentShape(.rect)
                    }
                } else {
                    Text(text)
                }
            }
            .font(CSFont.caption(12))
            .foregroundStyle(CSColor.inkSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func attributionText(_ image: CatalogImage) -> String {
        var text = String(localized: "Immagine: \(image.author) · \(image.license) · Wikimedia Commons")
        if image.modified { text += " · " + String(localized: "modificata") }
        return text
    }
}

// MARK: - Carta grande

/// Carta grande con inclinazione. Possiede il `MotionManager`: è l'unica view che legge
/// roll e pitch, così il giroscopio (60 Hz) non rivaluta il resto del dettaglio.
private struct ModelHeroCard: View {
    let entry: AlbumModelEntry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = MotionManager()

    private enum Metrics {
        static let maxWidth: CGFloat = 280
        static let tilt: Double = 8
        static let perspective: CGFloat = 0.6
    }

    var body: some View {
        // Con Reduce Motion la carta resta ferma.
        let roll = reduceMotion ? 0 : motion.roll
        let pitch = reduceMotion ? 0 : motion.pitch
        ModelCardView(entry: entry, style: .hero, roll: roll, pitch: pitch)
            .rotation3DEffect(.degrees(roll * Metrics.tilt), axis: (x: 0, y: 1, z: 0),
                              perspective: Metrics.perspective)
            .rotation3DEffect(.degrees(-pitch * Metrics.tilt), axis: (x: 1, y: 0, z: 0),
                              perspective: Metrics.perspective)
            .frame(maxWidth: Metrics.maxWidth)
            .padding(.top, CSSpace.sm)
            .onAppear { if !reduceMotion { motion.start() } }
            .onDisappear { motion.stop() }
    }
}

// MARK: - Riga versione

private struct VersionRow: View {
    let row: AlbumVariantRow
    let bodyType: BodyType
    /// Foto dell'utente per le righe "Altra versione".
    let card: StoredCard?

    private enum Metrics {
        static let thumbnail: CGFloat = 52
        static let dot: CGFloat = 7
    }

    var body: some View {
        // Ad accessibilità grande la riga va in colonna.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CSSpace.sm) {
                thumbnail
                texts
                Spacer(minLength: CSSpace.xs)
                copiesPill
            }
            VStack(alignment: .leading, spacing: CSSpace.xs) {
                thumbnail
                texts
                copiesPill
            }
        }
        .padding(.horizontal, CSSpace.md)
        .padding(.vertical, CSSpace.sm)
        .frame(maxWidth: .infinity, minHeight: CSSize.minTap, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let card {
                PhotoThumbnail(card: card)
                    .clipShape(RoundedRectangle(cornerRadius: CSRadius.sm - 4, style: .continuous))
            } else {
                CatalogImageView(image: row.image, bodyType: bodyType, silhouette: !row.isFound,
                                 maxPixel: 160,
                                 tint: row.isFound ? row.rarity.color.opacity(0.5) : albumSilhouette)
            }
        }
        .frame(width: Metrics.thumbnail, height: Metrics.thumbnail)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: CSSpace.xxs) {
            Text(row.name)
                .font(CSFont.body(16))
                .foregroundStyle(row.isFound ? CSColor.ink : CSColor.inkSecondary)
                .lineLimit(3)
            HStack(spacing: CSSpace.xs) {
                Circle().fill(row.rarity.color).frame(width: Metrics.dot, height: Metrics.dot)
                Text(row.rarity.displayName)
                if row.isOtherVersion { Text("· Altra versione") }
            }
            .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
        }
    }

    @ViewBuilder private var copiesPill: some View {
        if row.copies > 1 { CountPill("×\(row.copies)") }
    }

    private var spoken: String {
        var parts = [row.name, row.rarity.localizedName]
        if row.isOtherVersion { parts.append(String(localized: "altra versione")) }
        parts.append(row.isFound ? String(localized: "trovata") : String(localized: "da trovare"))
        if row.copies > 1 { parts.append(String(localized: "\(row.copies) copie")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Foto dell'utente

/// Miniatura già decodificata, passabile tra isolation.
private struct DecodedPhoto: @unchecked Sendable {
    let image: CGImage
}

/// Decodifica ImageIO fuori dal main actor.
@concurrent
private func decodePhoto(_ data: Data, maxPixel: Int) async -> DecodedPhoto? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return DecodedPhoto(image: cg)
}

/// Foto quadrata della carta, decodificata in miniatura; senza foto un glifo di ripiego.
private struct PhotoThumbnail: View {
    let card: StoredCard
    @State private var decoded: DecodedPhoto?

    /// Si rifà la miniatura quando la foto arriva dal cloud (stessa carta, prima senza foto).
    private struct Key: Hashable {
        let id: UUID
        let hasPhoto: Bool
    }

    var body: some View {
        Color.clear
            .overlay {
                if let decoded {
                    Image(decorative: decoded.image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "car.side.fill").foregroundStyle(albumSilhouette)
                }
            }
            .clipped()
            .background(CSColor.nested.opacity(0.5))
            .task(id: Key(id: card.id, hasPhoto: card.photo != nil)) {
                guard let data = card.photo else { decoded = nil; return }
                decoded = await decodePhoto(data, maxPixel: 300)
            }
    }
}

/// Cella della griglia "Le tue foto": tocco -> dettaglio della singola carta.
private struct PhotoCell: View {
    let card: StoredCard
    @Environment(SyncService.self) private var sync: SyncService?

    var body: some View {
        NavigationLink {
            CardDetailView(card: card.asSpotCard)
        } label: {
            PhotoThumbnail(card: card)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous))
                // Foto ripristinata dal cloud: si scarica solo quando la cella appare.
                .task(id: card.id) { await sync?.loadPhotoIfNeeded(cardId: card.id) }
        }
        .buttonStyle(CSPressStyle())
        .accessibilityLabel(Text("Foto del \(card.capturedAt.formatted(date: .abbreviated, time: .omitted))"))
    }
}
