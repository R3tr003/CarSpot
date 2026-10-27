import Testing
import Foundation
@testable import CarSpot

/// Normalizzazione, ricerca tollerante e suggerimenti.
struct CatalogSearchTests {
    private let index = TestCatalog.index

    private func found(_ query: String) -> Set<String> {
        let terms = index.terms(for: query)
        return Set(index.makes.flatMap { index.models(ofMake: $0.id) }
            .filter { index.matches(model: $0, terms: terms) }.map(\.id))
    }

    @Test func normalizza() {
        #expect(CatalogText.normalize("  Dobló ") == "doblo")
        #expect(CatalogText.normalize("Citroën  C3") == "citroen c3")
        #expect(CatalogText.normalize("Alfa-Romeo_Giulia") == "alfa romeo giulia")
    }

    @Test func refusoEAccenti() {
        #expect(found("golff").contains("volkswagen-golf"))
        #expect(found("Dobló") == ["fiat-doblo"])
        #expect(found("citroen c3") == ["citroen-c3"])
        #expect(found("  CITROËN   c3 ") == ["citroen-c3"])
    }

    @Test func piuParole() {
        #expect(found("alfa giulia") == ["alfa-romeo-giulia"])
        #expect(found("golf gti") == ["volkswagen-golf"])
        #expect(found("fiat 500") == ["fiat-500", "fiat-500-1957"])
    }

    @Test func prefisso() {
        #expect(found("giu") == ["alfa-romeo-giulia"])
        #expect(found("fer") == ["ferrari-f8", "ferrari-250-gto"])
    }

    @Test func nessunRisultato() {
        #expect(found("xq").isEmpty)
        #expect(found("zzzzzz").isEmpty)
    }

    @Test func queryVuotaTrovaTutto() {
        #expect(found("   ").count == index.modelCount)
    }

    @Test func unaModificaSoloDaQuattroLettere() {
        // "gol" è prefisso; "gilf" ha 4 lettere e dista 1 da "golf"; "gi" non è tollerata.
        #expect(found("gilf").contains("volkswagen-golf"))
        #expect(!found("gx").contains("volkswagen-golf"))
    }

    @Test func suggerimenti() {
        #expect(index.suggestions(for: "fe").contains("Ferrari"))
        #expect(index.suggestions(for: "fiat 5").first == "Fiat 500")
        #expect(index.suggestions(for: "fe", limit: 1).count == 1)
        #expect(index.suggestions(for: "").isEmpty)
        #expect(index.suggestions(for: "zz").isEmpty)
    }

    @Test func ordinamenti() {
        #expect(index.makes.map(\.id) == ["alfa-romeo", "citroen", "ferrari", "fiat", "volkswagen"])
        // Popolarità decrescente.
        #expect(index.models(ofMake: "fiat").map(\.id) == ["fiat-500", "fiat-panda", "fiat-500-1957", "fiat-doblo"])
        // Base prima, poi per nome.
        #expect(index.variants(ofModel: "volkswagen-golf").map(\.id)
                == ["volkswagen-golf", "volkswagen-golf-gti", "volkswagen-golf-r"])
        #expect(index.baseVariant(ofModel: "alfa-romeo-giulia")?.id == "alfa-romeo-giulia")
    }

    @Test func omonimiConAnno() throws {
        let old = try #require(index.model(id: "fiat-500-1957"))
        let new = try #require(index.model(id: "fiat-500"))
        let panda = try #require(index.model(id: "fiat-panda"))
        #expect(index.displayName(of: old) == "500 (1957)")
        #expect(index.displayName(of: new) == "500 (2007)")
        #expect(index.displayName(of: panda) == "Panda")
    }

    @Test func rarita() throws {
        let gto = try #require(index.baseVariant(ofModel: "ferrari-250-gto"))
        // Stessa regola delle carte catturate.
        #expect(index.catalogRarity(of: gto) == RarityEngine.assess(make: "Ferrari", model: "250 GTO", year: 1962).rarity)
    }
}
