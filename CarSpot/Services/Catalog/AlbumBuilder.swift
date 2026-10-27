import Foundation

/// Carta posseduta, copiata dallo `StoredCard` (le ripetizioni non arrivano qui).
struct OwnedCard: Sendable, Hashable {
    let id: UUID
    let make: String
    let model: String
    let year: Int
    let rarity: Rarity
    let capturedAt: Date
}

enum Ownership: CaseIterable, Sendable {
    case all, found, missing

    var title: LocalizedStringResource {
        switch self {
        case .all: "Tutte"
        case .found: "Trovate"
        case .missing: "Da trovare"
        }
    }
}

struct AlbumFilters: Equatable, Sendable {
    var ownership = Ownership.all
    var rarity: Rarity?
    var bodyType: BodyType?
    var country: String?
    /// Decennio di inizio produzione; 1970 = "Classiche" (prima del 1980).
    var era: Int?
    var query = ""

    /// Pillole o ricerca attive (le carte fuori catalogo non hanno quei dati).
    var isNarrowed: Bool {
        hasPill || !CatalogText.normalize(query).isEmpty
    }

    var hasPill: Bool {
        rarity != nil || bodyType != nil || country != nil || era != nil
    }
}

struct AlbumVariantRow: Identifiable, Sendable {
    let id: String
    let name: String
    let rarity: Rarity
    let copies: Int
    let image: CatalogImage?
    let isFound: Bool
    let isOtherVersion: Bool
    let cardIDs: [UUID]
}

struct AlbumModelEntry: Identifiable, Sendable {
    /// Id del modello.
    let id: String
    let makeName: String
    let name: String
    let bodyType: BodyType
    let rarity: Rarity
    let isFound: Bool
    let copies: Int
    let isNew: Bool
    let versionsFound: Int
    let versionsTotal: Int
    let image: CatalogImage?
}

struct AlbumSection: Identifiable, Sendable {
    /// Id della marca, oppure `AlbumBuilder.uncatalogedID`.
    let id: String
    let title: String
    let found: Int
    let total: Int
    let models: [AlbumModelEntry]
    let orphans: [OwnedCard]
}

struct AlbumStats: Equatable, Sendable {
    var modelsFound = 0
    var makesStarted = 0
    var makesComplete = 0
}

/// Abbinamento carta -> catalogo, precalcolato: va rifatto solo quando cambiano le carte.
struct AlbumMatches: Sendable {
    let cards: [OwnedCard]
    fileprivate let variantCards: [String: [OwnedCard]]
    fileprivate let otherCards: [String: [OwnedCard]]
    fileprivate let modelCards: [String: [OwnedCard]]
    fileprivate let orphansByMake: [String: [OwnedCard]]
    fileprivate let looseOrphans: [OwnedCard]

    init(cards: [OwnedCard], matcher: CatalogMatcher) {
        var variantCards: [String: [OwnedCard]] = [:]
        var otherCards: [String: [OwnedCard]] = [:]
        var modelCards: [String: [OwnedCard]] = [:]
        var orphansByMake: [String: [OwnedCard]] = [:]
        var looseOrphans: [OwnedCard] = []

        // Dalla più recente: tutte le liste restano in quest'ordine.
        for card in cards.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            switch matcher.match(make: card.make, model: card.model, year: card.year) {
            case .variant(let id):
                guard let variant = matcher.index.variant(id: id) else { looseOrphans.append(card); continue }
                variantCards[id, default: []].append(card)
                modelCards[variant.modelId, default: []].append(card)
            case .otherVersion(let modelId):
                otherCards[modelId, default: []].append(card)
                modelCards[modelId, default: []].append(card)
            case .unmatched(let makeId?):
                orphansByMake[makeId, default: []].append(card)
            case .unmatched(nil):
                looseOrphans.append(card)
            }
        }
        self.cards = cards
        self.variantCards = variantCards
        self.otherCards = otherCards
        self.modelCards = modelCards
        self.orphansByMake = orphansByMake
        self.looseOrphans = looseOrphans
    }

    /// Carte del modello (versioni e "altra versione"), la più recente prima.
    func cards(forModel modelId: String) -> [OwnedCard] { modelCards[modelId] ?? [] }
}

/// Costruzione dell'album: logica pura, da chiamare fuori dal `body`.
enum AlbumBuilder {
    static let uncatalogedID = "fuori-catalogo"
    private static let newWindow: TimeInterval = 7 * 86_400

    static func build(index: CatalogIndex, matches: AlbumMatches, filters: AlbumFilters,
                      now: Date) -> (sections: [AlbumSection], stats: AlbumStats) {
        let terms = index.terms(for: filters.query)
        let showOrphans = filters.ownership != .missing && !filters.hasPill
        let newSince = now.addingTimeInterval(-newWindow)

        var sections: [AlbumSection] = []
        var stats = AlbumStats()

        for make in index.makes {
            let models = index.models(ofMake: make.id)
            let countryOK = filters.country == nil || filters.country == make.country
            var found = 0
            var visible: [AlbumModelEntry] = []

            for model in models {
                let cards = matches.modelCards[model.id]
                let isFound = cards?.isEmpty == false
                if isFound { found += 1 }

                // Filtri economici prima, poi si costruisce la voce.
                guard countryOK else { continue }
                switch filters.ownership {
                case .all: break
                case .found: if !isFound { continue }
                case .missing: if isFound { continue }
                }
                if let body = filters.bodyType, model.bodyType != body { continue }
                if let era = filters.era, !inEra(model.yearStart, era: era) { continue }
                if !terms.isEmpty && !index.matches(model: model, terms: terms) { continue }

                let entry = entry(for: model, make: make, cards: cards ?? [], index: index,
                                  matches: matches, newSince: newSince)
                if let rarity = filters.rarity, entry.rarity != rarity { continue }
                visible.append(entry)
            }

            stats.modelsFound += found
            if found > 0 { stats.makesStarted += 1 }
            if !models.isEmpty && found == models.count { stats.makesComplete += 1 }

            let orphans = showOrphans
                ? visibleOrphans(matches.orphansByMake[make.id] ?? [], terms: terms)
                : []
            if !visible.isEmpty || !orphans.isEmpty {
                sections.append(AlbumSection(id: make.id, title: make.name, found: found,
                                             total: models.count, models: visible, orphans: orphans))
            }
        }

        // Carte senza marca nota: in fondo all'album.
        let loose = showOrphans ? visibleOrphans(matches.looseOrphans, terms: terms) : []
        if !loose.isEmpty {
            sections.append(AlbumSection(id: uncatalogedID, title: String(localized: "Fuori catalogo"),
                                         found: 0, total: 0, models: [], orphans: loose))
        }
        return (sections, stats)
    }

    /// Righe del dettaglio: una per versione del catalogo (base prima), poi "altra versione".
    static func variantRows(modelId: String, index: CatalogIndex, matches: AlbumMatches) -> [AlbumVariantRow] {
        let base = index.baseVariant(ofModel: modelId)
        var rows: [AlbumVariantRow] = index.variants(ofModel: modelId).map { variant in
            let cards = matches.variantCards[variant.id] ?? []
            return AlbumVariantRow(
                id: variant.id, name: variant.name,
                rarity: highestRarity(cards) ?? index.catalogRarity(of: variant),
                copies: cards.count,
                image: variant.image ?? base?.image,
                isFound: !cards.isEmpty, isOtherVersion: false,
                cardIDs: cards.map(\.id)
            )
        }

        // Carte del modello senza versione nota: una riga per nome scritto sulla carta.
        let others = matches.otherCards[modelId] ?? []
        var order: [String] = []
        var groups: [String: [OwnedCard]] = [:]
        for card in others {
            let key = CardCopies.key(make: card.make, model: card.model)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(card)
        }
        for key in order {
            guard let cards = groups[key], let first = cards.first else { continue }
            rows.append(AlbumVariantRow(
                id: "altra-\(modelId)-\(key)", name: first.model,
                rarity: highestRarity(cards) ?? .comune, copies: cards.count,
                image: nil, isFound: true, isOtherVersion: true, cardIDs: cards.map(\.id)
            ))
        }
        return rows
    }

    // MARK: - Dettagli

    private static func entry(for model: CatalogModel, make: CatalogMake, cards: [OwnedCard],
                              index: CatalogIndex, matches: AlbumMatches, newSince: Date) -> AlbumModelEntry {
        let variants = index.variants(ofModel: model.id)
        let base = variants.first { $0.isBase }
        let isFound = !cards.isEmpty

        let rarity: Rarity
        if let best = highestRarity(cards) {
            rarity = best
        } else if let base {
            rarity = index.catalogRarity(of: base)
        } else {
            rarity = .comune
        }

        var versionsFound = 0
        var foundImage: CatalogImage?
        for variant in variants where matches.variantCards[variant.id]?.isEmpty == false {
            versionsFound += 1
            if foundImage == nil { foundImage = variant.image }
        }

        // Le carte vanno dalla più recente: l'ultima è la prima copia.
        let isNew = (cards.last?.capturedAt).map { $0 >= newSince } ?? false

        return AlbumModelEntry(
            id: model.id, makeName: make.name, name: index.displayName(of: model),
            bodyType: model.bodyType, rarity: rarity, isFound: isFound, copies: cards.count,
            isNew: isNew, versionsFound: versionsFound, versionsTotal: variants.count,
            image: foundImage ?? base?.image
        )
    }

    private static func highestRarity(_ cards: [OwnedCard]) -> Rarity? {
        cards.max { rank($0.rarity) < rank($1.rarity) }?.rarity
    }

    /// Posizione nella scala Comune < ... < Leggendaria.
    private static func rank(_ rarity: Rarity) -> Int {
        switch rarity {
        case .comune: 0
        case .rara: 1
        case .epica: 2
        case .leggendaria: 3
        }
    }

    /// Con la ricerca, le carte fuori catalogo contano per il loro nome.
    private static func visibleOrphans(_ cards: [OwnedCard], terms: [String]) -> [OwnedCard] {
        guard !terms.isEmpty else { return cards }
        return cards.filter { CatalogText.matches(words: CatalogText.words("\($0.make) \($0.model)"), terms: terms) }
    }

    /// 1970 = "Classiche" (prima del 1980); altrimenti il decennio di inizio produzione.
    private static func inEra(_ yearStart: Int?, era: Int) -> Bool {
        guard let yearStart else { return false }
        return era <= 1970 ? yearStart < 1980 : (yearStart / 10) * 10 == era
    }
}
