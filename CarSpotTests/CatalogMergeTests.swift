import Testing
import Foundation
@testable import CarSpot

/// Unione delle novità remote nello snapshot.
struct CatalogMergeTests {
    @Test func mergeUpsertERimozione() throws {
        let base = TestCatalog.snapshot
        let later = TestCatalog.date.addingTimeInterval(3_600)

        // Una versione aggiornata (nuovo nome), una cancellata, un modello nuovo con la sua base.
        let gti = try #require(base.variants.first { $0.id == "volkswagen-golf-gti" })
        let renamed = CatalogVariant(id: gti.id, modelId: gti.modelId, name: "Golf GTI Clubsport", isBase: false,
                                     yearStart: gti.yearStart, yearEnd: nil, aliases: [], updatedAt: later, image: nil)
        let newModel = TestCatalog.model("fiat-tipo", "fiat", "Tipo", .berlina, 2016)
        let newBase = TestCatalog.variant("fiat-tipo", "fiat-tipo", "Tipo", base: true, 2016)

        let changes = CatalogChanges(
            models: [newModel], variants: [renamed, newBase],
            deletedVariantIds: ["volkswagen-golf-r"]
        )
        let merged = base.merging(changes)

        #expect(merged.variants.first { $0.id == "volkswagen-golf-gti" }?.name == "Golf GTI Clubsport")
        #expect(!merged.variants.contains { $0.id == "volkswagen-golf-r" })
        #expect(merged.models.contains { $0.id == "fiat-tipo" })
        #expect(merged.variants.contains { $0.id == "fiat-tipo" })
        #expect(merged.variants.count == base.variants.count + 1 - 1)
        #expect(merged.models.count == base.models.count + 1)
        #expect(merged.makes == base.makes)
        #expect(merged.newestUpdate == later)

        // L'indice riflette l'unione.
        let index = CatalogIndex(merged)
        #expect(index.variants(ofModel: "volkswagen-golf").map(\.id) == ["volkswagen-golf", "volkswagen-golf-gti"])
        #expect(index.models(ofMake: "fiat").contains { $0.id == "fiat-tipo" })
    }

    @Test func nessunaNovitaNonCambiaNiente() {
        let base = TestCatalog.snapshot
        #expect(CatalogChanges().isEmpty)
        #expect(base.merging(CatalogChanges()) == base)
    }

    @Test func marcaCancellataSparisceDallIndice() {
        let merged = TestCatalog.snapshot.merging(CatalogChanges(deletedMakeIds: ["ferrari"]))
        let index = CatalogIndex(merged)
        #expect(!index.makes.contains { $0.id == "ferrari" })
        // I modelli senza marca non entrano nell'indice.
        #expect(index.model(id: "ferrari-f8") == nil)
        #expect(index.modelCount == TestCatalog.index.modelCount - 2)
    }
}
