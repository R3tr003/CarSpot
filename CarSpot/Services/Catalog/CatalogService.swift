import Foundation

/// Novità del catalogo dopo una data: righe nuove o cambiate, più gli id cancellati.
struct CatalogChanges: Sendable {
    var makes: [CatalogMake] = []
    var models: [CatalogModel] = []
    var variants: [CatalogVariant] = []
    var deletedMakeIds: Set<String> = []
    var deletedModelIds: Set<String> = []
    var deletedVariantIds: Set<String> = []

    var isEmpty: Bool {
        makes.isEmpty && models.isEmpty && variants.isEmpty
            && deletedMakeIds.isEmpty && deletedModelIds.isEmpty && deletedVariantIds.isEmpty
    }
}

/// Fonte delle novità del catalogo. Il punto di partenza è lo snapshot nel bundle.
protocol CatalogService: Sendable {
    func changes(since: Date) async throws -> CatalogChanges
}

extension CatalogSnapshot {
    /// Upsert per id (le righe nuove in coda), poi le rimozioni.
    func merging(_ c: CatalogChanges) -> CatalogSnapshot {
        CatalogSnapshot(
            version: version,
            generatedAt: generatedAt,
            imageBaseURL: imageBaseURL,
            makes: Self.upsert(makes, with: c.makes, removing: c.deletedMakeIds),
            models: Self.upsert(models, with: c.models, removing: c.deletedModelIds),
            variants: Self.upsert(variants, with: c.variants, removing: c.deletedVariantIds)
        )
    }

    private static func upsert<T: Identifiable>(_ current: [T], with updates: [T],
                                                removing removed: Set<String>) -> [T] where T.ID == String {
        var result = current
        var position: [String: Int] = [:]
        position.reserveCapacity(current.count)
        for (i, item) in current.enumerated() { position[item.id] = i }
        for item in updates {
            if let i = position[item.id] {
                result[i] = item
            } else {
                position[item.id] = result.count
                result.append(item)
            }
        }
        return removed.isEmpty ? result : result.filter { !removed.contains($0.id) }
    }
}
