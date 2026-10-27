import Foundation
import Supabase

/// Novità del catalogo da Supabase (`car_makes`, `car_models`, `car_variants`):
/// solo le righe con `updated_at` successivo, comprese quelle cancellate (`deleted_at`).
struct SupabaseCatalogService: CatalogService {
    let client: SupabaseClient

    private static let pageSize = 1000

    func changes(since: Date) async throws -> CatalogChanges {
        let from = CatalogJSON.formatDate(since)
        var changes = CatalogChanges()

        for row in try await pages("car_makes", since: from, as: MakeRow.self) {
            if row.deleted_at != nil { changes.deletedMakeIds.insert(row.id) } else { changes.makes.append(row.model) }
        }
        for row in try await pages("car_models", since: from, as: ModelRow.self) {
            if row.deleted_at != nil { changes.deletedModelIds.insert(row.id) } else { changes.models.append(row.model) }
        }
        for row in try await pages("car_variants", since: from, as: VariantRow.self) {
            if row.deleted_at != nil { changes.deletedVariantIds.insert(row.id) } else { changes.variants.append(row.model) }
        }
        return changes
    }

    /// Pagine da 1000 righe, in ordine stabile.
    private func pages<Row: Decodable & Sendable>(_ table: String, since: String, as: Row.Type) async throws -> [Row] {
        var all: [Row] = []
        var offset = 0
        while true {
            let page: [Row] = try await client.from(table)
                .select()
                .gt("updated_at", value: since)
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value
            all += page
            if page.count < Self.pageSize { return all }
            offset += Self.pageSize
        }
    }

    // MARK: - Righe remote (snake_case)

    private struct MakeRow: Decodable, Sendable {
        let id: String
        let name: String
        let country: String?
        let aliases: [String]?
        let updated_at: String
        let deleted_at: String?

        var model: CatalogMake {
            CatalogMake(id: id, name: name, country: country, aliases: aliases ?? [],
                        updatedAt: CatalogJSON.parseDate(updated_at) ?? .distantPast)
        }
    }

    private struct ModelRow: Decodable, Sendable {
        let id: String
        let make_id: String
        let name: String
        let body_type: String
        let year_start: Int?
        let year_end: Int?
        let popularity: Int?
        let aliases: [String]?
        let updated_at: String
        let deleted_at: String?

        var model: CatalogModel {
            CatalogModel(id: id, makeId: make_id, name: name,
                         bodyType: BodyType(rawValue: body_type) ?? .berlina,
                         yearStart: year_start, yearEnd: year_end, popularity: popularity ?? 0,
                         aliases: aliases ?? [],
                         updatedAt: CatalogJSON.parseDate(updated_at) ?? .distantPast)
        }
    }

    private struct VariantRow: Decodable, Sendable {
        let id: String
        let model_id: String
        let name: String
        let is_base: Bool
        let year_start: Int?
        let year_end: Int?
        let aliases: [String]?
        let image_path: String?
        let image_width: Int?
        let image_height: Int?
        let image_title: String?
        let image_author: String?
        let image_license: String?
        let image_license_url: String?
        let image_source_url: String?
        let image_modified: Bool?
        let updated_at: String
        let deleted_at: String?

        var model: CatalogVariant {
            var image: CatalogImage?
            if let image_path {
                image = CatalogImage(
                    path: image_path, width: image_width ?? 0, height: image_height ?? 0,
                    title: image_title ?? "", author: image_author ?? "", license: image_license ?? "",
                    licenseURL: image_license_url.flatMap(URL.init(string:)),
                    sourceURL: image_source_url.flatMap(URL.init(string:)),
                    modified: image_modified ?? false
                )
            }
            return CatalogVariant(id: id, modelId: model_id, name: name, isBase: is_base,
                                  yearStart: year_start, yearEnd: year_end, aliases: aliases ?? [],
                                  updatedAt: CatalogJSON.parseDate(updated_at) ?? .distantPast,
                                  image: image)
        }
    }
}
