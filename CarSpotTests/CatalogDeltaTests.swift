import Testing
import Foundation
@testable import CarSpot

/// Punto di partenza delle novità remote: mai l'ultima riga già in cache.
struct CatalogDeltaTests {
    @Test(arguments: [
        // Dal server (microsecondi) e dalla cache (millisecondi troncati).
        ("2026-10-27T21:10:41.921125Z", "2026-10-27T21:10:41.922Z"),
        ("2026-10-27T21:10:41.921Z", "2026-10-27T21:10:41.922Z"),
        ("2026-10-27T21:10:41.999Z", "2026-10-27T21:10:42.000Z"),
        // Snapshot del bundle, al secondo.
        ("2026-10-27T21:01:29Z", "2026-10-27T21:01:29.001Z")
    ])
    func partePoiDelMillisecondo(_ text: String, _ expected: String) throws {
        let date = try #require(CatalogJSON.parseDate(text))
        #expect(SupabaseCatalogService.afterMillisecond(of: date) == expected)
    }
}
