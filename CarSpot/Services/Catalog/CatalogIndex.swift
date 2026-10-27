import Foundation

/// Normalizzazione dei testi per ricerca e abbinamento.
enum CatalogText {
    /// Minuscole, senza diacritici, `-`/`_` come spazi, spazi compressi
    /// (stesse regole di spazi di `CardCopies.key`).
    static func normalize(_ s: String) -> String {
        String(
            s.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .map { $0 == "-" || $0 == "_" ? " " : $0 }
        )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Parole del testo già normalizzato.
    static func words(_ s: String) -> [String] {
        normalize(s).split(separator: " ").map(String.init)
    }

    /// Ogni parola della query deve essere prefisso di una parola del testo, oppure
    /// (query di almeno 4 lettere) distare al massimo una modifica da una di esse.
    static func matches(words: [String], terms: [String]) -> Bool {
        for term in terms {
            let tolerant = term.count >= 4
            let hit = words.contains { word in
                word.hasPrefix(term) || (tolerant && withinOneEdit(term, word))
            }
            if !hit { return false }
        }
        return true
    }

    /// Distanza di Levenshtein <= 1 (sostituzione, inserimento o cancellazione).
    static func withinOneEdit(_ a: String, _ b: String) -> Bool {
        if abs(a.utf8.count - b.utf8.count) > 1 { return false }
        let x = Array(a.utf8), y = Array(b.utf8)
        var i = 0, j = 0, edits = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (x.count - i) + (y.count - j) <= 1
    }
}

/// Indice in sola lettura del catalogo: ricerca per id, ordinamenti e ricerca testuale.
/// Si costruisce una volta (fuori dal main actor) e si riusa; i modelli di marche
/// sconosciute vengono ignorati.
struct CatalogIndex: Sendable {
    /// Marche in ordine alfabetico.
    let makes: [CatalogMake]

    private let makesByID: [String: CatalogMake]
    private let modelsByID: [String: CatalogModel]
    private let variantsByID: [String: CatalogVariant]
    private let modelsByMake: [String: [CatalogModel]]
    private let variantsByModel: [String: [CatalogVariant]]
    private let searchWords: [String: [String]]
    private let rarityByVariant: [String: Rarity]
    private let homonymIDs: Set<String>
    private let suggestionPool: [Suggestion]

    private struct Suggestion: Sendable {
        let key: String
        let title: String
    }

    init(_ snapshot: CatalogSnapshot) {
        let makesByID = Dictionary(snapshot.makes.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let sortedMakes = makesByID.values
            .map { (key: CatalogText.normalize($0.name), make: $0) }
            .sorted { ($0.key, $0.make.id) < ($1.key, $1.make.id) }
            .map(\.make)

        // Modelli per marca: più popolari prima, poi per nome.
        let knownModels = snapshot.models.filter { makesByID[$0.makeId] != nil }
        let modelsByID = Dictionary(knownModels.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var grouped: [String: [CatalogModel]] = [:]
        for model in modelsByID.values { grouped[model.makeId, default: []].append(model) }
        var modelsByMake: [String: [CatalogModel]] = [:]
        var homonyms = Set<String>()
        for (makeId, list) in grouped {
            let keyed = list.map { (key: CatalogText.normalize($0.name), model: $0) }
            modelsByMake[makeId] = keyed.sorted {
                if $0.model.popularity != $1.model.popularity { return $0.model.popularity > $1.model.popularity }
                return ($0.key, $0.model.id) < ($1.key, $1.model.id)
            }.map(\.model)
            // Omonimi (500 del 1957 e del 2007): servono per mostrare l'anno.
            let byName = Dictionary(grouping: keyed, by: \.key)
            for group in byName.values where group.count > 1 {
                homonyms.formUnion(group.map(\.model.id))
            }
        }

        // Versioni per modello: la base prima, poi per nome.
        let knownVariants = snapshot.variants.filter { modelsByID[$0.modelId] != nil }
        let variantsByID = Dictionary(knownVariants.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var variantGroups: [String: [CatalogVariant]] = [:]
        for variant in variantsByID.values { variantGroups[variant.modelId, default: []].append(variant) }
        var variantsByModel: [String: [CatalogVariant]] = [:]
        for (modelId, list) in variantGroups {
            variantsByModel[modelId] = list
                .map { (key: CatalogText.normalize($0.name), variant: $0) }
                .sorted {
                    if $0.variant.isBase != $1.variant.isBase { return $0.variant.isBase }
                    return ($0.key, $0.variant.id) < ($1.key, $1.variant.id)
                }
                .map(\.variant)
        }

        // Parole cercabili: marca + modello + alias del modello + nomi delle versioni.
        var searchWords: [String: [String]] = [:]
        searchWords.reserveCapacity(modelsByID.count)
        for model in modelsByID.values {
            var text = makesByID[model.makeId]?.name ?? ""
            text += " " + model.name
            for alias in model.aliases { text += " " + alias }
            for variant in variantsByModel[model.id] ?? [] { text += " " + variant.name }
            searchWords[model.id] = Array(Set(CatalogText.words(text)))
        }

        // Rarità del catalogo: la stessa regola delle carte catturate.
        var rarityByVariant: [String: Rarity] = [:]
        rarityByVariant.reserveCapacity(variantsByID.count)
        for variant in variantsByID.values {
            guard let model = modelsByID[variant.modelId], let make = makesByID[model.makeId] else { continue }
            rarityByVariant[variant.id] = RarityEngine.assess(
                make: make.name, model: variant.name, year: variant.yearStart ?? model.yearStart
            ).rarity
        }

        // Suggerimenti: prima le marche, poi "Marca Modello" per popolarità.
        var pool = sortedMakes.map { Suggestion(key: CatalogText.normalize($0.name), title: $0.name) }
        var seen = Set(pool.map(\.key))
        for make in sortedMakes {
            for model in modelsByMake[make.id] ?? [] {
                let title = "\(make.name) \(model.name)"
                let key = CatalogText.normalize(title)
                if seen.insert(key).inserted { pool.append(Suggestion(key: key, title: title)) }
            }
        }

        self.makes = sortedMakes
        self.makesByID = makesByID
        self.modelsByID = modelsByID
        self.variantsByID = variantsByID
        self.modelsByMake = modelsByMake
        self.variantsByModel = variantsByModel
        self.searchWords = searchWords
        self.rarityByVariant = rarityByVariant
        self.homonymIDs = homonyms
        self.suggestionPool = pool
    }

    // MARK: - Accesso

    var modelCount: Int { modelsByID.count }

    func make(id: String) -> CatalogMake? { makesByID[id] }
    func model(id: String) -> CatalogModel? { modelsByID[id] }
    func variant(id: String) -> CatalogVariant? { variantsByID[id] }

    func models(ofMake makeId: String) -> [CatalogModel] { modelsByMake[makeId] ?? [] }
    func variants(ofModel modelId: String) -> [CatalogVariant] { variantsByModel[modelId] ?? [] }
    func baseVariant(ofModel modelId: String) -> CatalogVariant? { variantsByModel[modelId]?.first { $0.isBase } }

    /// Nome da mostrare: con l'anno se la marca ha un altro modello omonimo ("500 (1957)").
    func displayName(of model: CatalogModel) -> String {
        guard homonymIDs.contains(model.id), let year = model.yearStart else { return model.name }
        return "\(model.name) (\(year))"
    }

    /// Rarità stimata dal catalogo (per le versioni non ancora trovate).
    func catalogRarity(of variant: CatalogVariant) -> Rarity {
        if let cached = rarityByVariant[variant.id] { return cached }
        guard let model = modelsByID[variant.modelId], let make = makesByID[model.makeId] else { return .comune }
        return RarityEngine.assess(make: make.name, model: variant.name,
                                   year: variant.yearStart ?? model.yearStart).rarity
    }

    // MARK: - Ricerca

    /// Parole normalizzate della query (vuoto = nessun filtro).
    func terms(for query: String) -> [String] { CatalogText.words(query) }

    func matches(model: CatalogModel, terms: [String]) -> Bool {
        terms.isEmpty || CatalogText.matches(words: searchWords[model.id] ?? [], terms: terms)
    }

    func matches(model: CatalogModel, query: String) -> Bool {
        matches(model: model, terms: terms(for: query))
    }

    /// Nomi di marca e "Marca Modello" che iniziano con la query.
    func suggestions(for query: String, limit: Int = 5) -> [String] {
        let q = CatalogText.normalize(query)
        guard !q.isEmpty, limit > 0 else { return [] }
        var result: [String] = []
        for item in suggestionPool where item.key.hasPrefix(q) && item.key != q {
            result.append(item.title)
            if result.count == limit { break }
        }
        return result
    }
}
