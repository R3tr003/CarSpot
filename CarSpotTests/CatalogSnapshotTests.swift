import Testing
import Foundation
@testable import CarSpot

/// Formato dello snapshot (contratto tra pipeline e app).
struct CatalogSnapshotTests {
    private static let json = """
    {
      "version": 1,
      "generatedAt": "2026-10-25T18:00:00Z",
      "imageBaseURL": "https://example.com/car-models/",
      "makes": [{"id":"fiat","name":"Fiat","country":"IT","aliases":["FIAT"],"updatedAt":"2026-10-20T10:00:00Z"}],
      "models": [{"id":"fiat-panda","makeId":"fiat","name":"Panda","bodyType":"station_wagon",
                  "yearStart":1980,"yearEnd":null,"popularity":85,"aliases":[],"updatedAt":"2026-10-22T10:00:00Z"}],
      "variants": [
        {"id":"fiat-panda","modelId":"fiat-panda","name":"Panda","isBase":true,"yearStart":1980,"yearEnd":null,
         "aliases":[],"updatedAt":"2026-10-24T09:30:00.500Z",
         "image":{"path":"fiat/fiat-panda.webp","width":512,"height":301,"title":"File:Panda.jpg","author":"Mario",
                  "license":"CC BY-SA 4.0","licenseURL":"https://creativecommons.org/licenses/by-sa/4.0/",
                  "sourceURL":"https://commons.wikimedia.org/wiki/File:Panda.jpg","modified":true}},
        {"id":"fiat-panda-4x4","modelId":"fiat-panda","name":"Panda 4x4","isBase":false,"yearStart":1983,"yearEnd":null,
         "aliases":[],"updatedAt":"2026-10-21T10:00:00Z","image":null}
      ]
    }
    """

    @Test func decodeFixture() throws {
        let snapshot = try CatalogSnapshot.decode(Data(Self.json.utf8))
        #expect(snapshot.makes.count == 1)
        #expect(snapshot.models.first?.bodyType == .stationWagon)
        #expect(snapshot.models.first?.yearEnd == nil)
        #expect(snapshot.variants.count == 2)
        #expect(snapshot.variants[0].image?.license == "CC BY-SA 4.0")
        #expect(snapshot.variants[0].image?.modified == true)
        #expect(snapshot.variants[1].image == nil)
    }

    @Test func imageURLConcatena() throws {
        let snapshot = try CatalogSnapshot.decode(Data(Self.json.utf8))
        let image = try #require(snapshot.variants[0].image)
        #expect(snapshot.imageURL(for: image).absoluteString == "https://example.com/car-models/fiat/fiat-panda.webp")
    }

    @Test func newestUpdate() throws {
        let snapshot = try CatalogSnapshot.decode(Data(Self.json.utf8))
        // La riga più recente ha anche frazioni di secondo.
        let expected = try #require(CatalogJSON.parseDate("2026-10-24T09:30:00.500Z"))
        #expect(snapshot.newestUpdate == expected)
    }

    @Test func codificaERilettura() throws {
        let snapshot = try CatalogSnapshot.decode(Data(Self.json.utf8))
        let again = try CatalogSnapshot.decode(snapshot.encoded())
        #expect(again == snapshot)
    }

    @Test func bundleContieneLoSnapshot() throws {
        let snapshot = try CatalogSnapshot.bundled()
        #expect(!snapshot.makes.isEmpty)
        #expect(snapshot.models.allSatisfy { m in snapshot.makes.contains { $0.id == m.makeId } })
        #expect(snapshot.variants.allSatisfy { v in snapshot.models.contains { $0.id == v.modelId } })
    }
}
