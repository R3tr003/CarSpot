import SwiftUI
import SwiftData

/// Collezione come album continuo: marche una dopo l'altra con i modelli del catalogo
/// (trovati a colori, mancanti come ombra), ricerca, filtri e indice A–Z.
/// Il calcolo dell'album sta in `AlbumModel`, mai nel `body`.
struct CollectionView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    // Le ripetizioni (stessa auto già catturata) restano in cronologia, non in collezione.
    @Query(filter: #Predicate<StoredCard> { $0.isRepeat == false },
           sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @State private var model = AlbumModel()
    @State private var cardsByID: [UUID: StoredCard] = [:]
    @FocusState private var searchFocused: Bool
    @Namespace private var zoomNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: CSSpace.sm), count: 3)
    private let orphanColumns = Array(repeating: GridItem(.flexible(), spacing: CSSpace.md), count: 2)

    /// Cambia quando cambiano le carte che contano per l'album.
    private var cardsSignature: Int {
        var hasher = Hasher()
        for card in stored {
            hasher.combine(card.id)
            hasher.combine(card.make)
            hasher.combine(card.model)
            hasher.combine(card.rarityRaw)
        }
        return hasher.finalize()
    }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var showsIndexBar: Bool {
        model.isReady && !typeSize.isAccessibilitySize
            && model.sections.count >= AlbumIndexBar.minimumSections && model.indexEntries.count > 1
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CSSpace.md) {
                        controls
                        content
                    }
                    .padding(.horizontal, CSSpace.lg)
                    .padding(.top, CSSpace.lg)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .trailing) {
                    if showsIndexBar {
                        AlbumIndexBar(entries: model.indexEntries) { id in
                            proxy.scrollTo(id, anchor: .top)
                        }
                        // Tetto al Dynamic Type: la misura delle lettere lo vede.
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .padding(.trailing, 2)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Sfondo trasparente: sopra la card si deve vedere la mappa.
            .containerBackground(.clear, for: .navigation)
            .scrollContentBackground(.hidden)
        }
        .task { await CatalogStore.shared.load() }
        .onChange(of: cardsSignature, initial: true) {
            cardsByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            model.update(cards: stored.map {
                OwnedCard(id: $0.id, make: $0.make, model: $0.model, year: $0.year,
                          rarity: $0.rarity, capturedAt: $0.capturedAt)
            })
        }
    }

    // MARK: - Testata e controlli

    @ViewBuilder private var controls: some View {
        SheetHeader(title: "Collezione")

        if model.isReady && !isSearching {
            KPIStrip([
                .init("Modelli trovati", value: compact(model.stats.modelsFound)),
                .init("Marche iniziate", value: compact(model.stats.makesStarted)),
                .init("Complete", value: compact(model.stats.makesComplete))
            ])
        }

        AlbumSearchField(
            text: Binding(get: { model.searchText }, set: { model.setSearchText($0) }),
            isFocused: $searchFocused,
            onSubmit: {
                model.commitSearch(model.searchText)
                searchFocused = false
            },
            onClear: { model.commitSearch("") }
        )

        if searchFocused {
            let items = model.suggestions()
            if !items.isEmpty {
                AlbumSuggestions(items: items) { pick in
                    model.commitSearch(pick)
                    searchFocused = false
                }
            }
        }

        AlbumOwnershipPicker(selection: model.filters.ownership) { model.setOwnership($0) }
        AlbumPillRow(model: model)
    }

    // MARK: - Contenuto

    @ViewBuilder private var content: some View {
        if !model.isReady {
            // Al massimo un frame: lo snapshot sta nel bundle.
            Surface(.group) {
                Text("Sto preparando l'album…")
                    .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        } else {
            if !model.hasCards { firstCardBanner }
            if model.sections.isEmpty {
                noResults
            } else {
                album
            }
        }
    }

    private var album: some View {
        LazyVStack(alignment: .leading, spacing: CSSpace.md, pinnedViews: [.sectionHeaders]) {
            ForEach(model.sections) { section in
                Section {
                    sectionBody(section)
                } header: {
                    SectionHeader(section: section).id(section.id)
                }
            }
        }
        .padding(.trailing, showsIndexBar ? 14 : 0)
    }

    private func sectionBody(_ section: AlbumSection) -> some View {
        VStack(alignment: .leading, spacing: CSSpace.md) {
            if !section.models.isEmpty {
                LazyVGrid(columns: columns, spacing: CSSpace.sm) {
                    ForEach(section.models) { entry in
                        NavigationLink {
                            ModelDetailView(modelId: entry.id, initialEntry: entry)
                                .navigationTransition(.zoom(sourceID: entry.id, in: zoomNamespace))
                        } label: {
                            ModelCardView(entry: entry)
                                .matchedTransitionSource(id: entry.id, in: zoomNamespace)
                        }
                        .buttonStyle(CSPressStyle())
                    }
                }
            }
            if !section.orphans.isEmpty {
                if section.id != AlbumBuilder.uncatalogedID {
                    Text("Fuori catalogo").eyebrow().accessibilityAddTraits(.isHeader)
                }
                LazyVGrid(columns: orphanColumns, spacing: CSSpace.md) {
                    ForEach(section.orphans, id: \.id) { orphan in
                        if let card = cardsByID[orphan.id] {
                            OrphanCell(card: card, namespace: zoomNamespace)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stati vuoti

    private var firstCardBanner: some View {
        Surface(.group) {
            HStack(spacing: CSSpace.md) {
                Image(systemName: "camera.viewfinder")
                    .font(CSFont.title(22))
                    .foregroundStyle(CSColor.accent)
                    .accessibilityHidden(true)
                Text("Cattura la tua prima auto per iniziare l'album")
                    .font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noResults: some View {
        Surface(.group) {
            VStack(spacing: CSSpace.md) {
                if let last = model.lastFilter {
                    Text("Nessun modello trovato")
                        .font(CSFont.title(20)).foregroundStyle(CSColor.ink)
                    GhostButton(title: label(for: last)) { model.clear(last) }
                    if model.activeOrder.count > 1 {
                        GhostButton(title: "Mostra tutte") { model.resetAll() }
                    }
                } else {
                    // Nessun filtro attivo: il catalogo è vuoto, non c'è un'uscita da offrire.
                    Text("Il catalogo non è disponibile. Riprova più tardi.")
                        .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func label(for kind: AlbumFilterKind) -> LocalizedStringKey {
        let name = model.title(of: kind)
        return kind == .query ? "Cancella la ricerca" : "Togli il filtro \(name)"
    }

    private func compact(_ value: Int) -> String {
        value > 999 ? value.formatted(.number.notation(.compactName).locale(.app)) : "\(value)"
    }
}

// MARK: - Intestazione di marca

/// Nome, barretta di progresso e "5/9"; resta agganciata in alto mentre scorri la marca.
/// Con Dynamic Type da accessibilità nome e conteggio vanno in colonna, senza barretta.
private struct SectionHeader: View {
    let section: AlbumSection
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Metrics {
        static let barWidth: CGFloat = 44
        static let barHeight: CGFloat = 4
    }

    private var progress: Double {
        section.total > 0 ? Double(section.found) / Double(section.total) : 0
    }

    private var countText: some View {
        Text("\(section.found)/\(section.total)")
            .font(CSFont.caption(13)).monospacedDigit()
            .foregroundStyle(CSColor.inkSecondary)
    }

    private var titleText: some View {
        Text(section.title)
            .font(CSFont.title(17)).foregroundStyle(CSColor.ink)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .layoutPriority(1)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    titleText
                    if section.total > 0 { countText }
                }
            } else {
                HStack(spacing: CSSpace.sm) {
                    titleText
                    if section.total > 0 {
                        Capsule().fill(CSColor.nested)
                            .frame(width: Metrics.barWidth, height: Metrics.barHeight)
                            .overlay(alignment: .leading) {
                                Capsule().fill(CSColor.accent)
                                    .frame(width: Metrics.barWidth * progress)
                            }
                            .accessibilityHidden(true)
                        Spacer(minLength: CSSpace.xs)
                        countText
                    }
                }
            }
        }
        .padding(.vertical, CSSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CSColor.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityValue(section.total > 0
                            ? String(localized: "\(section.found) su \(section.total)") : "")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Carta fuori catalogo

/// Foto dell'utente di un'auto che il catalogo non conosce: resta visibile come prima.
private struct OrphanCell: View {
    let card: StoredCard
    let namespace: Namespace.ID
    @Environment(SyncService.self) private var sync: SyncService?

    var body: some View {
        let spot = card.asSpotCard
        NavigationLink {
            CardDetailView(card: spot)
                .navigationTransition(.zoom(sourceID: spot.id, in: namespace))
        } label: {
            SpotCardView(card: spot, compact: true)
                .matchedTransitionSource(id: spot.id, in: namespace)
                // Foto ripristinata dal cloud: si scarica solo quando la carta appare.
                .task(id: spot.id) { await sync?.loadPhotoIfNeeded(cardId: spot.id) }
        }
        .buttonStyle(CSPressStyle())
    }
}

#Preview { CollectionView().preferredColorScheme(.dark) }
