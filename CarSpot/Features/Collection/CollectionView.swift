import SwiftUI
import SwiftData

/// Collezione come album continuo: marche una dopo l'altra con i modelli del catalogo
/// (trovati a colori, mancanti come ombra), ricerca, filtri e indice A–Z.
/// Il calcolo dell'album sta in `AlbumModel`, mai nel `body`.
struct CollectionView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SyncService.self) private var sync: SyncService?
    // Le ripetizioni (stessa auto già catturata) restano in cronologia, non in collezione.
    @Query(filter: #Predicate<StoredCard> { $0.isRepeat == false },
           sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @State private var model = AlbumModel()
    @State private var tracker = AlbumScrollTracker()
    @State private var cardsByID: [UUID: StoredCard] = [:]
    /// Altezza della testata agganciata: misura la zona che sparisce sotto di lei.
    @State private var headerHeight: CGFloat = 32
    /// Altezza visibile dell'album (cambia con il detent del pannello).
    @State private var viewportHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @Namespace private var zoomNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: CSSpace.sm), count: 3)

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

    /// Primo ripristino dal cloud con la collezione ancora vuota: le carte stanno arrivando.
    private var isRestoringFirst: Bool {
        sync?.isRestoring == true && !model.hasCards
    }

    /// L'album ha l'indice A–Z: il suo spazio a destra resta fisso, anche quando è nascosto,
    /// così la griglia non si ridispone mentre scorri.
    private var hasIndex: Bool {
        model.isReady && !typeSize.isAccessibilitySize
            && model.sections.count >= AlbumIndexBar.minimumSections && model.indexEntries.count > 1
    }

    /// Pannello basso (200 pt): la testata agganciata ruberebbe metà dello spazio.
    private var stickyEnabled: Bool { viewportHeight >= AlbumLayout.minStickyViewport }

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
                    .padding(.bottom, CSSize.tabBarClearance)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Testata della marca senza fascia: le carte spariscono sotto e sfumano.
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { viewportHeight = $0 }
                .topEdgeFade(hidden: AlbumLayout.stickyTop + headerHeight,
                             active: stickyEnabled && tracker.isActive)
                .overlay(alignment: .top) {
                    if stickyEnabled {
                        AlbumStickyHeader(model: model, tracker: tracker,
                                          trailing: hasIndex ? AlbumLayout.indexGutter : 0) { height in
                            if abs(height - headerHeight) > 0.5 { headerHeight = height }
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    if hasIndex && stickyEnabled {
                        AlbumIndexOverlay(entries: model.indexEntries, tracker: tracker,
                                          top: AlbumLayout.stickyTop + headerHeight + CSSpace.xs) { id in
                            jump(to: id, proxy: proxy)
                        }
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
        .onChange(of: model.sections.map(\.id), initial: true) { _, ids in
            tracker.sync(order: ids)
        }
    }

    // MARK: - Testata e controlli

    @ViewBuilder private var controls: some View {
        SheetHeader(title: "Collezione")

        if !model.isReady || (isRestoringFirst && !isSearching) {
            KPIStripSkeleton()
        } else if !isSearching {
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
            // Al massimo un frame (lo snapshot sta nel bundle): scheletro nella forma dell'album.
            albumSkeleton
        } else {
            if !model.hasCards && !isRestoringFirst { firstCardBanner }
            if model.sections.isEmpty {
                noResults
            } else {
                album
            }
        }
    }

    /// Testata di marca e 3×3 carte finte: non lazy, sono poche e fisse.
    private var albumSkeleton: some View {
        VStack(alignment: .leading, spacing: CSSpace.sm) {
            HStack(spacing: CSSpace.sm) {
                SkeletonLine(width: SkeletonMetrics.titleWidth, height: SkeletonMetrics.titleHeight)
                SkeletonLine(width: SkeletonMetrics.barWidth, height: SkeletonMetrics.barHeight)
            }
            .padding(.vertical, CSSpace.xs)
            ForEach(0..<SkeletonMetrics.rows, id: \.self) { _ in
                HStack(spacing: CSSpace.sm) {
                    ForEach(0..<SkeletonMetrics.columns, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: CSRadius.sm)
                            .aspectRatio(SkeletonMetrics.cardRatio, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonLoading()
    }

    private enum SkeletonMetrics {
        static let rows = 3
        static let columns = 3
        static let cardRatio: CGFloat = 0.7
        static let titleWidth: CGFloat = 96
        static let titleHeight: CGFloat = 14
        static let barWidth: CGFloat = 44
        static let barHeight: CGFloat = 4
    }

    /// Una sola griglia lazy per tutto l'album (niente griglie annidate in una lista lazy:
    /// davano carte fantasma fuori posto). Le testate scorrono con la marca; quella
    /// agganciata in alto è `AlbumStickyHeader`.
    private var album: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: CSSpace.sm) {
            ForEach(model.sections) { section in
                Section {
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
                } header: {
                    sectionHeader(section)
                } footer: {
                    if !section.orphans.isEmpty { orphans(section) }
                }
            }
        }
        .padding(.trailing, hasIndex ? AlbumLayout.indexGutter : 0)
    }

    /// Salto dall'indice: la testata atterra dove sta quella agganciata, così la prima riga
    /// di carte non finisce sotto la sfumatura. Le posizioni vecchie non valgono più.
    private func jump(to id: String, proxy: ScrollViewProxy) {
        tracker.reset()
        let free = max(1, viewportHeight - headerHeight)
        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: AlbumLayout.stickyTop / free))
    }

    private func sectionHeader(_ section: AlbumSection) -> some View {
        SectionHeader(section: section)
            .id(section.id)
            // Punti interi: i decimali di layout facevano oscillare l'azione tra due valori.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY.rounded() } action: { minY in
                tracker.report(section.id, minY: minY)
            }
            .onDisappear { tracker.remove(section.id) }
            .padding(.top, section.id == model.sections.first?.id ? 0 : CSSpace.sm)
    }

    /// Foto dell'utente fuori catalogo, a due colonne (poche: niente griglia lazy).
    private func orphans(_ section: AlbumSection) -> some View {
        let rows = stride(from: 0, to: section.orphans.count, by: 2).map {
            Array(section.orphans[$0..<min($0 + 2, section.orphans.count)])
        }
        return VStack(alignment: .leading, spacing: CSSpace.md) {
            if section.id != AlbumBuilder.uncatalogedID {
                Text("Fuori catalogo").eyebrow().accessibilityAddTraits(.isHeader)
            }
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: CSSpace.md) {
                    ForEach(row, id: \.id) { orphan in
                        Group {
                            if let card = cardsByID[orphan.id] {
                                OrphanCell(card: card, namespace: zoomNamespace)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .padding(.top, section.models.isEmpty ? 0 : CSSpace.xs)
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

/// Nome, barretta di progresso e "5/9", senza fondo: in linea scorre con la marca,
/// una copia resta agganciata in alto (`AlbumStickyHeader`).
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityValue(section.total > 0
                            ? String(localized: "\(section.found) su \(section.total)") : "")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Testata agganciata e indice

/// Misure dell'album condivise da griglia, testata agganciata e indice.
private enum AlbumLayout {
    /// Distanza della testata agganciata dal bordo alto (sotto la maniglia del pannello).
    static let stickyTop: CGFloat = CSSpace.md
    /// Spazio a destra della griglia riservato all'indice A–Z.
    static let indexGutter: CGFloat = 14
    /// Sotto quest'altezza visibile niente testata agganciata né indice.
    static let minStickyViewport: CGFloat = 220
}

/// Quale marca sta sotto la testata agganciata. Le testate in linea riportano la loro
/// posizione; `CollectionView` legge solo `isActive`, così scorrere non la ricalcola.
@MainActor
@Observable
private final class AlbumScrollTracker {
    /// Marca della testata agganciata; `nil` finché i controlli in alto sono visibili.
    private(set) var current: String?
    private(set) var isActive = false

    @ObservationIgnored private var positions: [String: CGFloat] = [:]
    @ObservationIgnored private var order: [String] = []

    func sync(order: [String]) {
        self.order = order
        let valid = Set(order)
        positions = positions.filter { valid.contains($0.key) }
        if let current, !valid.contains(current) { set(nil) }
        recompute()
    }

    /// Dopo un salto lungo: le testate ancora vive ma lontane hanno posizioni vecchie.
    /// La marca corrente resta finché le testate visibili non si riportano.
    func reset() {
        positions = [:]
    }

    func report(_ id: String, minY: CGFloat) {
        positions[id] = minY
        recompute()
    }

    func remove(_ id: String) {
        positions[id] = nil
        recompute()
    }

    private func recompute() {
        let threshold = AlbumLayout.stickyTop + 0.5
        if let passed = positions.filter({ $0.value <= threshold }).max(by: { $0.value < $1.value }) {
            // L'ultima testata salita fino alla posizione agganciata.
            set(passed.key)
        } else if let below = positions.min(by: { $0.value < $1.value }),
                  let index = order.firstIndex(of: below.key) {
            // Tutte le testate visibili sono più in basso: vale la marca prima della prima.
            set(index > 0 ? order[index - 1] : nil)
        }
        // Nessuna testata visibile (in mezzo a una marca lunga): resta quella di prima.
    }

    private func set(_ id: String?) {
        if current != id { current = id }
        if isActive != (id != nil) { isActive = id != nil }
    }
}

/// Copia agganciata della testata di marca: stessa vista, nessun fondo (le carte sotto
/// spariscono con `topEdgeFade`). VoiceOver legge le testate in linea.
private struct AlbumStickyHeader: View {
    let model: AlbumModel
    let tracker: AlbumScrollTracker
    let trailing: CGFloat
    let onHeight: (CGFloat) -> Void

    var body: some View {
        if let id = tracker.current, let section = model.sections.first(where: { $0.id == id }) {
            SectionHeader(section: section)
                .padding(.leading, CSSpace.lg)
                .padding(.trailing, CSSpace.lg + trailing)
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { onHeight($0) }
                .padding(.top, AlbumLayout.stickyTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Indice A–Z solo nell'album: compare quando i controlli in alto sono scrollati via,
/// tra la testata agganciata e la tab bar. Se lì non ci sta, resta nascosto.
private struct AlbumIndexOverlay: View {
    let entries: [AlbumIndexBar.Entry]
    let tracker: AlbumScrollTracker
    let top: CGFloat
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if tracker.isActive {
                ViewThatFits(in: .vertical) {
                    AlbumIndexBar(entries: entries, onSelect: onSelect)
                        // Tetto al Dynamic Type: la misura delle lettere lo vede.
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    Color.clear.frame(width: 0, height: 0)
                }
                .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, top)
        .padding(.bottom, CSSize.tabBarHeight)
        .padding(.trailing, 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tracker.isActive)
    }
}

// MARK: - Carta fuori catalogo

/// Foto dell'utente di un'auto che il catalogo non conosce: resta visibile come prima.
private struct OrphanCell: View {
    let card: StoredCard
    let namespace: Namespace.ID
    @Environment(SyncService.self) private var sync: SyncService?

    var body: some View {
        let spot = card.asSpotCard(failedPhotos: sync?.failedPhotos ?? [])
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
