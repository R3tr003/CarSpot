import SwiftUI
import Observation

/// Risultato di una costruzione dell'album.
private struct AlbumResult: Sendable {
    let sections: [AlbumSection]
    let stats: AlbumStats
}

/// Abbinamento carte-catalogo fuori dal main actor (serve anche al dettaglio del modello).
@concurrent
func makeAlbumMatches(cards: [OwnedCard], matcher: CatalogMatcher) async -> AlbumMatches {
    AlbumMatches(cards: cards, matcher: matcher)
}

@concurrent
private func buildAlbum(index: CatalogIndex, matches: AlbumMatches,
                        filters: AlbumFilters, now: Date) async -> AlbumResult {
    let result = AlbumBuilder.build(index: index, matches: matches, filters: filters, now: now)
    return AlbumResult(sections: result.sections, stats: result.stats)
}

/// Filtri attivi, nell'ordine in cui l'utente li ha accesi (serve a "togli l'ultimo").
enum AlbumFilterKind: Hashable {
    case ownership, rarity, bodyType, country, era, query
}

/// Epoche selezionabili: 1970 = "Classiche" (prima del 1980).
enum AlbumEra {
    static let all = [1970, 1980, 1990, 2000, 2010, 2020]

    static func title(_ era: Int) -> String {
        switch era {
        case ...1970: String(localized: "Classiche")
        case 1980: String(localized: "Anni '80")
        case 1990: String(localized: "Anni '90")
        default: String(localized: "Anni \(era)")
        }
    }
}

/// Stato della schermata Collezione: filtri, sezioni e numeri sono calcolati qui, fuori dal
/// `body` e fuori dal main actor, solo quando cambiano carte, catalogo o filtri.
@MainActor
@Observable
final class AlbumModel {
    private(set) var filters = AlbumFilters()
    /// Testo nel campo di ricerca; `filters.query` lo segue con 150 ms di ritardo.
    private(set) var searchText = ""
    private(set) var sections: [AlbumSection] = []
    private(set) var stats = AlbumStats()
    /// `false` finché il catalogo non è pronto: la vista mostra "Sto preparando l'album…".
    private(set) var isReady = false
    private(set) var hasCards = false
    private(set) var countries: [String] = []
    private(set) var activeOrder: [AlbumFilterKind] = []
    /// Iniziali per l'indice A–Z, calcolate una volta per costruzione.
    private(set) var indexEntries: [AlbumIndexBar.Entry] = []

    @ObservationIgnored private var cards: [OwnedCard] = []
    @ObservationIgnored private var matches: AlbumMatches?
    @ObservationIgnored private var matchesStale = true
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isObserving = false

    private static let queryDelay: Duration = .milliseconds(150)

    // MARK: - Ingressi

    /// Da chiamare quando cambiano le carte salvate.
    func update(cards: [OwnedCard]) {
        self.cards = cards
        hasCards = !cards.isEmpty
        matchesStale = true
        observeCatalog()
        rebuild()
    }

    /// Il catalogo si ripubblica dopo l'aggiornamento remoto: l'album va rifatto.
    private func observeCatalog() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = CatalogStore.shared.index
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.matchesStale = true
                self.observeCatalog()
                self.rebuild()
            }
        }
    }

    // MARK: - Filtri

    func setSearchText(_ text: String) {
        searchText = text
        queryTask?.cancel()
        guard text != filters.query else { return }
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.queryDelay)
            guard !Task.isCancelled else { return }
            self?.applyQuery(text)
        }
    }

    /// Applica subito la ricerca (suggerimento, invio, ✕).
    func commitSearch(_ text: String) {
        searchText = text
        queryTask?.cancel()
        applyQuery(text)
    }

    private func applyQuery(_ text: String) {
        guard filters.query != text else { return }
        filters.query = text
        markActive(.query, active: !CatalogText.normalize(text).isEmpty)
        rebuild()
    }

    func setOwnership(_ value: Ownership) {
        guard filters.ownership != value else { return }
        filters.ownership = value
        markActive(.ownership, active: value != .all)
        track(value == .all ? "all" : (value == .found ? "found" : "missing"))
        rebuild(animated: true)
    }

    func setRarity(_ value: Rarity?) {
        filters.rarity = value
        markActive(.rarity, active: value != nil)
        track(value.map { "rarity:\(String(describing: $0))" } ?? "all")
        rebuild(animated: true)
    }

    func setBodyType(_ value: BodyType?) {
        filters.bodyType = value
        markActive(.bodyType, active: value != nil)
        track(value.map { "body:\($0.rawValue)" } ?? "all")
        rebuild(animated: true)
    }

    func setCountry(_ value: String?) {
        filters.country = value
        markActive(.country, active: value != nil)
        track(value.map { "country:\($0)" } ?? "all")
        rebuild(animated: true)
    }

    func setEra(_ value: Int?) {
        filters.era = value
        markActive(.era, active: value != nil)
        track(value.map { "era:\($0)" } ?? "all")
        rebuild(animated: true)
    }

    func clear(_ kind: AlbumFilterKind) {
        switch kind {
        case .ownership: setOwnership(.all)
        case .rarity: setRarity(nil)
        case .bodyType: setBodyType(nil)
        case .country: setCountry(nil)
        case .era: setEra(nil)
        case .query: commitSearch("")
        }
    }

    func resetAll() {
        queryTask?.cancel()
        searchText = ""
        filters = AlbumFilters()
        activeOrder = []
        track("all")
        rebuild(animated: true)
    }

    /// Ultimo filtro acceso ancora attivo (per "Togli il filtro SUV").
    var lastFilter: AlbumFilterKind? { activeOrder.last }

    /// Nome leggibile di un filtro attivo, per il bottone di uscita.
    func title(of kind: AlbumFilterKind) -> String {
        switch kind {
        case .ownership: String(localized: filters.ownership.title)
        case .rarity: filters.rarity?.localizedName ?? ""
        case .bodyType: filters.bodyType?.localizedName ?? ""
        case .country: filters.country.map { Locale.app.localizedString(forRegionCode: $0) ?? $0 } ?? ""
        case .era: filters.era.map(AlbumEra.title) ?? ""
        case .query: filters.query
        }
    }

    /// Fino a 5 suggerimenti per la query in corso (marca o "Marca Modello").
    func suggestions() -> [String] {
        guard let index = CatalogStore.shared.index else { return [] }
        return index.suggestions(for: searchText, limit: 5)
    }

    // MARK: - Costruzione

    private func markActive(_ kind: AlbumFilterKind, active: Bool) {
        activeOrder.removeAll { $0 == kind }
        if active { activeOrder.append(kind) }
    }

    private func track(_ filter: String) {
        AppServices.analytics.track(.collectionFiltered(filter: filter))
    }

    /// `animated` solo per i cambi discreti (segmentato, pillole), mai per la query.
    private func rebuild(animated: Bool = false) {
        buildTask?.cancel()
        generation += 1
        let gen = generation

        let store = CatalogStore.shared
        guard let index = store.index, let matcher = store.matcher else {
            isReady = false
            return
        }
        let cards = cards
        let filters = filters
        let needMatches = matchesStale || matches == nil
        let known = matches

        buildTask = Task { [weak self] in
            let current: AlbumMatches
            if needMatches || known == nil {
                current = await makeAlbumMatches(cards: cards, matcher: matcher)
            } else if let known {
                current = known
            } else { return }
            let result = await buildAlbum(index: index, matches: current, filters: filters, now: .now)
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            if needMatches { self.matchesStale = false }
            self.matches = current
            let entries = AlbumIndexBar.entries(for: result.sections)
            let animation: Animation? = animated && !UIAccessibility.isReduceMotionEnabled
                ? .spring(duration: 0.3, bounce: 0) : nil
            withAnimation(animation) {
                self.sections = result.sections
                self.stats = result.stats
                self.indexEntries = entries
                self.isReady = true
            }
            self.refreshCountries(index)
        }
    }

    @ObservationIgnored private var countriesFor = -1

    /// Paesi delle marche del catalogo, in ordine di nome (si ricalcola solo se cambia il catalogo).
    private func refreshCountries(_ index: CatalogIndex) {
        guard countriesFor != index.modelCount + index.makes.count else { return }
        countriesFor = index.modelCount + index.makes.count
        let codes = Set(index.makes.compactMap(\.country))
        countries = codes.sorted {
            (Locale.app.localizedString(forRegionCode: $0) ?? $0)
                .localizedCaseInsensitiveCompare(Locale.app.localizedString(forRegionCode: $1) ?? $1) == .orderedAscending
        }
    }
}
