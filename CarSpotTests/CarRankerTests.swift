import Testing
import Foundation
@testable import CarSpot

/// Classifica on-device: famiglie unite, popolarità, file del bundle coerenti.
struct CarRankerTests {

    /// Tre modelli in 2D: "A5" e "A5 8T" sono la stessa famiglia (indice 0).
    private func ranker() throws -> CarRanker {
        let labels = """
        {"dim":2,"logitScale":10,"popularityWeight":0,"models":[
         {"id":"audi-a5","make":"Audi","model":"A5","family":0,"popularity":36,"yearStart":2007,"yearEnd":2016},
         {"id":"audi-a5-8t","make":"Audi","model":"A5 8T","family":0,"popularity":5,"yearStart":null,"yearEnd":null},
         {"id":"fiat-panda","make":"Fiat","model":"Panda","family":2,"popularity":32,"yearStart":null,"yearEnd":null}]}
        """
        let rows: [Float16] = [1, 0, 0.9, 0.436, 0, 1]
        let vectors = rows.withUnsafeBufferPointer { Data(buffer: $0) }
        return try CarRanker(labels: Data(labels.utf8), vectors: vectors)
    }

    @Test func uniscePerFamiglia() throws {
        let result = try ranker().rank(embedding: [1, 0.1])
        #expect(result.map(\.title) == ["Audi A5", "Fiat Panda"])
        // Somma di A5 e A5 8T: quasi tutta la probabilità.
        #expect(try #require(result.first).confidence > 0.9)
        #expect(result.first?.yearEstimate == 2011)
    }

    @Test func vettoreVuotoONonNormalizzato() throws {
        let r = try ranker()
        #expect(r.rank(embedding: [0, 0]).isEmpty)
        #expect(r.rank(embedding: [1]).isEmpty)
        #expect(r.rank(embedding: [0, 5]).first?.title == "Fiat Panda")
    }

    @Test func aParitàVinceIlPiùPopolare() throws {
        // Stesso vettore, popolarità diversa: decide solo il peso della popolarità.
        let labels = """
        {"dim":2,"logitScale":10,"popularityWeight":2,"models":[
         {"id":"rara","make":"X","model":"Rara","family":0,"popularity":2,"yearStart":null,"yearEnd":null},
         {"id":"comune","make":"X","model":"Comune","family":1,"popularity":50,"yearStart":null,"yearEnd":null}]}
        """
        let rows: [Float16] = [1, 0, 1, 0]
        let r = try CarRanker(labels: Data(labels.utf8), vectors: rows.withUnsafeBufferPointer { Data(buffer: $0) })
        let result = r.rank(embedding: [1, 0])
        #expect(result.map(\.model) == ["Comune", "Rara"])
        #expect(result.first?.yearEstimate == nil)
    }

    @Test func fileDelBundleAllineati() throws {
        let bundle = Bundle(for: BundleToken.self)
        let labels = try #require(bundle.url(forResource: "car-labels", withExtension: "json")
            ?? Bundle.main.url(forResource: "car-labels", withExtension: "json"))
        let vectors = try #require(bundle.url(forResource: "car-embeddings", withExtension: "f16")
            ?? Bundle.main.url(forResource: "car-embeddings", withExtension: "f16"))
        let ranker = try CarRanker(labels: Data(contentsOf: labels), vectors: Data(contentsOf: vectors))
        #expect(ranker.labels.models.count > 3000)
        #expect(ranker.labels.dim == 768)
    }
}

private final class BundleToken {}
