import Foundation

/// Esito dell'abbinamento di una carta salvata al catalogo.
enum CardMatch: Equatable, Sendable {
    /// Versione esatta del catalogo.
    case variant(id: String)
    /// Modello noto ma versione sconosciuta ("Altra versione").
    case otherVersion(modelId: String)
    /// Fuori catalogo; `makeId` se almeno la marca è nota.
    case unmatched(makeId: String?)
}

/// Abbina (marca, modello, anno) di una carta alla versione del catalogo.
/// Best effort: finché il riconoscimento non usa le etichette del catalogo.
struct CatalogMatcher: Sendable {
    let index: CatalogIndex

    /// Tabelle per marca: versioni per nome/alias e nomi di modello (più lunghi prima).
    private struct MakeTable: Sendable {
        var variantsByName: [String: [String]] = [:]
        var modelNames: [(name: String, modelId: String)] = []
    }

    private let makeIDs: [String: String]
    private let tables: [String: MakeTable]

    init(index: CatalogIndex) {
        self.index = index
        var makeIDs: [String: String] = [:]
        var tables: [String: MakeTable] = [:]
        for make in index.makes {
            for name in [make.name] + make.aliases {
                let key = CatalogText.normalize(name)
                if !key.isEmpty, makeIDs[key] == nil { makeIDs[key] = make.id }
            }
            var table = MakeTable()
            for model in index.models(ofMake: make.id) {
                for name in [model.name] + model.aliases {
                    let key = CatalogText.normalize(name)
                    if !key.isEmpty { table.modelNames.append((key, model.id)) }
                }
                for variant in index.variants(ofModel: model.id) {
                    for name in [variant.name] + variant.aliases {
                        let key = CatalogText.normalize(name)
                        if !key.isEmpty { table.variantsByName[key, default: []].append(variant.id) }
                    }
                }
            }
            table.modelNames.sort { $0.name.count > $1.name.count }
            tables[make.id] = table
        }
        self.makeIDs = makeIDs
        self.tables = tables
    }

    func match(make: String, model: String, year: Int) -> CardMatch {
        guard let makeId = makeIDs[CatalogText.normalize(make)] else { return .unmatched(makeId: nil) }
        let name = CatalogText.normalize(model)
        guard !name.isEmpty, let table = tables[makeId] else { return .unmatched(makeId: makeId) }

        // 1. Versione per nome o alias (omonimi: anni più vicini).
        if let ids = table.variantsByName[name],
           let best = closest(ids.compactMap { index.variant(id: $0) }, year: year) {
            return .variant(id: best.id)
        }

        // 2. Modello: il nome (o alias) più lungo che è il nome intero o ne è prefisso.
        var longest = 0
        var candidates: [String] = []
        for entry in table.modelNames {
            if longest > 0 && entry.name.count < longest { break }
            guard name == entry.name || name.hasPrefix(entry.name + " ") else { continue }
            longest = entry.name.count
            candidates.append(entry.modelId)
        }
        if longest > 0 {
            let models = Set(candidates).compactMap { index.model(id: $0) }
            if let best = closestModel(models, year: year) {
                // Nome del modello identico (via alias): è la versione base.
                if name.count == longest, let base = index.baseVariant(ofModel: best.id) {
                    return .variant(id: base.id)
                }
                return .otherVersion(modelId: best.id)
            }
        }
        return .unmatched(makeId: makeId)
    }

    // MARK: - Omonimi

    private func closest(_ variants: [CatalogVariant], year: Int) -> CatalogVariant? {
        variants.min { a, b in
            let ka = key(for: a, year: year), kb = key(for: b, year: year)
            return ka < kb
        }
    }

    private func closestModel(_ models: [CatalogModel], year: Int) -> CatalogModel? {
        models.min { a, b in
            (Self.distance(start: a.yearStart, end: a.yearEnd, year: year), -a.popularity, a.id)
                < (Self.distance(start: b.yearStart, end: b.yearEnd, year: year), -b.popularity, b.id)
        }
    }

    private func key(for variant: CatalogVariant, year: Int) -> (Int, Int, String) {
        let model = index.model(id: variant.modelId)
        let start = variant.yearStart ?? model?.yearStart
        let end = variant.yearEnd ?? model?.yearEnd
        return (Self.distance(start: start, end: end, year: year), -(model?.popularity ?? 0), variant.id)
    }

    /// Distanza in anni dall'intervallo di produzione (0 se dentro; estremi mancanti = aperti).
    private static func distance(start: Int?, end: Int?, year: Int) -> Int {
        if let start, year < start { return start - year }
        if let end, year > end { return year - end }
        return 0
    }
}
