import Foundation

/// Carrozzeria: insieme chiuso, uguale al `check` di `car_models.body_type`.
enum BodyType: String, CaseIterable, Codable, Sendable, Hashable {
    case utilitaria, berlina
    case stationWagon = "station_wagon"
    case suv, monovolume, coupe, cabrio, sportiva, pickup, furgone

    var displayName: LocalizedStringResource {
        switch self {
        case .utilitaria: "Utilitaria"
        case .berlina: "Berlina"
        case .stationWagon: "Station wagon"
        case .suv: "SUV"
        case .monovolume: "Monovolume"
        case .coupe: "Coupé"
        case .cabrio: "Cabrio"
        case .sportiva: "Sportiva"
        case .pickup: "Pick-up"
        case .furgone: "Furgone"
        }
    }

    /// Come `displayName`, già risolto in `String` (VoiceOver).
    var localizedName: String { String(localized: displayName) }

    /// SF Symbol di ripiego quando l'immagine del catalogo manca.
    var symbol: String {
        switch self {
        case .suv: "suv.side.fill"
        case .cabrio: "convertible.side.fill"
        case .pickup: "truck.pickup.side.fill"
        case .furgone, .monovolume: "bus.fill"
        case .utilitaria, .berlina, .stationWagon, .coupe, .sportiva: "car.side.fill"
        }
    }
}

struct CatalogMake: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let country: String?
    let aliases: [String]
    let updatedAt: Date
}

struct CatalogModel: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let makeId: String
    let name: String
    let bodyType: BodyType
    let yearStart: Int?
    let yearEnd: Int?
    let popularity: Int
    let aliases: [String]
    let updatedAt: Date
}

/// Immagine standard di una versione, con attribuzione Commons.
struct CatalogImage: Codable, Sendable, Hashable {
    let path: String
    let width: Int
    let height: Int
    let title: String
    let author: String
    let license: String
    let licenseURL: URL?
    let sourceURL: URL?
    let modified: Bool
}

struct CatalogVariant: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let modelId: String
    let name: String
    let isBase: Bool
    let yearStart: Int?
    let yearEnd: Int?
    let aliases: [String]
    let updatedAt: Date
    let image: CatalogImage?
}

struct CatalogSnapshot: Codable, Sendable, Hashable {
    let version: Int
    let generatedAt: Date
    let imageBaseURL: URL
    let makes: [CatalogMake]
    let models: [CatalogModel]
    let variants: [CatalogVariant]

    /// Nome della risorsa nel bundle (generata dalla pipeline in `tools/catalog`).
    static let resourceName = "catalog-snapshot"

    static func decode(_ data: Data) throws -> CatalogSnapshot {
        try CatalogJSON.decoder.decode(CatalogSnapshot.self, from: data)
    }

    func encoded() throws -> Data {
        try CatalogJSON.encoder.encode(self)
    }

    /// Snapshot incluso nell'app: funziona offline e per l'ospite.
    static func bundled(in bundle: Bundle = .main) throws -> CatalogSnapshot {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    /// Ultimo `updatedAt` tra tutte le righe: da qui si chiedono le novità al server.
    var newestUpdate: Date {
        var newest = Date.distantPast
        for m in makes where m.updatedAt > newest { newest = m.updatedAt }
        for m in models where m.updatedAt > newest { newest = m.updatedAt }
        for v in variants where v.updatedAt > newest { newest = v.updatedAt }
        return newest == .distantPast ? generatedAt : newest
    }

    func imageURL(for image: CatalogImage) -> URL {
        imageBaseURL.appending(path: image.path)
    }
}

/// Date ISO-8601 UTC, con o senza frazioni di secondo (Postgres le manda con).
enum CatalogJSON {
    static func parseDate(_ text: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true).parse(text) {
            return d
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    static func formatDate(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Data non valida: \(text)"))
            }
            return date
        }
        return d
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        return e
    }
}
