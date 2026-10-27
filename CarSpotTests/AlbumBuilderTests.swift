import Testing
import Foundation
@testable import CarSpot

/// Costruzione dell'album: progressi, filtri, rarità, nuove, orfani.
struct AlbumBuilderTests {
    private let index = TestCatalog.index
    private let matcher = TestCatalog.matcher
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ make: String, _ model: String, year: Int = 2015, rarity: Rarity = .comune,
                      daysAgo: Double = 30) -> OwnedCard {
        OwnedCard(id: UUID(), make: make, model: model, year: year, rarity: rarity,
                  capturedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    private func build(_ cards: [OwnedCard], _ filters: AlbumFilters = AlbumFilters())
        -> (sections: [AlbumSection], stats: AlbumStats) {
        AlbumBuilder.build(index: index, matches: AlbumMatches(cards: cards, matcher: matcher),
                           filters: filters, now: now)
    }

    private func entries(_ result: (sections: [AlbumSection], stats: AlbumStats)) -> [AlbumModelEntry] {
        result.sections.flatMap(\.models)
    }

    @Test func statsBase() {
        let none = build([])
        #expect(none.stats == AlbumStats(modelsFound: 0, makesStarted: 0, makesComplete: 0))
        #expect(none.sections.map(\.id) == ["alfa-romeo", "citroen", "ferrari", "fiat", "volkswagen"])

        // Due carte Fiat su due modelli: marca iniziata, non completa (la Fiat ne ha 4).
        let fiat = build([card("Fiat", "Panda"), card("Fiat", "Doblò")])
        #expect(fiat.stats == AlbumStats(modelsFound: 2, makesStarted: 1, makesComplete: 0))

        // Ferrari ha 2 modelli: tutti e due trovati = marca completa.
        let ferrari = build([card("Ferrari", "F8 Tributo"), card("Ferrari", "250 GTO")])
        #expect(ferrari.stats == AlbumStats(modelsFound: 2, makesStarted: 1, makesComplete: 1))
    }

    @Test func piuVersioniStessoModelloContanoUno() {
        let r = build([card("VW", "Golf"), card("VW", "Golf GTI"), card("VW", "Golf R")])
        #expect(r.stats.modelsFound == 1)
        let golf = entries(r).first { $0.id == "volkswagen-golf" }
        #expect(golf?.copies == 3)
        #expect(golf?.versionsFound == 3)
        #expect(golf?.versionsTotal == 3)
    }

    @Test func filtroDaTrovare() {
        let r = build([card("Fiat", "Panda")], AlbumFilters(ownership: .missing))
        let fiat = r.sections.first { $0.id == "fiat" }
        #expect(fiat?.models.map(\.id).contains("fiat-panda") == false)
        #expect(fiat?.models.count == 3)
        // Progressi della marca invariati dal filtro.
        #expect(fiat?.found == 1)
        #expect(fiat?.total == 4)
        #expect(r.stats.modelsFound == 1)
        #expect(entries(r).allSatisfy { !$0.isFound })
    }

    @Test func filtroTrovate() {
        let r = build([card("Fiat", "Panda")], AlbumFilters(ownership: .found))
        #expect(r.sections.map(\.id) == ["fiat"])
        #expect(entries(r).map(\.id) == ["fiat-panda"])
    }

    @Test func filtroRarita() {
        let cards = [card("Fiat", "500", year: 2015, rarity: .leggendaria)]
        let legendary = entries(build(cards, AlbumFilters(rarity: .leggendaria)))
        #expect(legendary.contains { $0.id == "fiat-500" })
        #expect(legendary.allSatisfy { $0.rarity == .leggendaria })
        // Conta il colore mostrato: la Fiat 500 è mostrata Leggendaria, non Comune.
        let common = entries(build(cards, AlbumFilters(rarity: .comune)))
        #expect(!common.contains { $0.id == "fiat-500" })
    }

    @Test func filtroCarrozzeriaEPaese() {
        let suv = build([], AlbumFilters(bodyType: .suv))
        #expect(suv.sections.map(\.id) == ["volkswagen"])
        #expect(entries(suv).map(\.id) == ["volkswagen-tiguan"])
        // Totale della marca = tutti i modelli, non solo quelli filtrati.
        #expect(suv.sections.first?.total == 2)

        let france = build([], AlbumFilters(country: "FR"))
        #expect(france.sections.map(\.id) == ["citroen"])
    }

    @Test func filtroEpocaClassiche() {
        let classics = entries(build([], AlbumFilters(era: 1970)))
        let ids = Set(classics.map(\.id))
        #expect(ids == ["ferrari-250-gto", "fiat-500-1957", "volkswagen-golf"])
        let eighties = entries(build([], AlbumFilters(era: 1980))).map(\.id)
        #expect(eighties == ["fiat-panda"])
        let tens = Set(entries(build([], AlbumFilters(era: 2010))).map(\.id))
        #expect(tens == ["alfa-romeo-giulia", "ferrari-f8"])
    }

    @Test func marcaVuotaOmessa() {
        let r = build([], AlbumFilters(query: "tiguan"))
        #expect(r.sections.map(\.id) == ["volkswagen"])
        #expect(build([], AlbumFilters(query: "xq")).sections.isEmpty)
    }

    @Test func nuovaSetteGiorni() {
        let recent = entries(build([card("Fiat", "Panda", daysAgo: 6)]))
        #expect(recent.first { $0.id == "fiat-panda" }?.isNew == true)
        let old = entries(build([card("Fiat", "Panda", daysAgo: 8)]))
        #expect(old.first { $0.id == "fiat-panda" }?.isNew == false)
        // Conta la PRIMA copia: una copia vecchia e una recente = non nuova.
        let both = entries(build([card("Fiat", "Panda", daysAgo: 20), card("Fiat", "Panda", daysAgo: 1)]))
        #expect(both.first { $0.id == "fiat-panda" }?.isNew == false)
        #expect(both.first { $0.id == "fiat-panda" }?.copies == 2)
    }

    @Test func rarSalvata() throws {
        let base = try #require(index.baseVariant(ofModel: "fiat-500"))
        let catalog = index.catalogRarity(of: base)
        #expect(catalog != .leggendaria)
        let r = build([card("Fiat", "500", rarity: .leggendaria), card("Fiat", "500", rarity: .rara)])
        #expect(entries(r).first { $0.id == "fiat-500" }?.rarity == .leggendaria)
        // Mancante: rarità del catalogo.
        #expect(entries(build([])).first { $0.id == "fiat-500" }?.rarity == catalog)
    }

    @Test func immagineDellaVersioneTrovata() {
        // Golf base ha immagine, GTI no: trovata solo la GTI -> ripiego sulla base.
        let r = entries(build([card("VW", "Golf GTI")]))
        #expect(r.first { $0.id == "volkswagen-golf" }?.image?.path == "x/volkswagen-golf.webp")
        // Modello senza immagine: nessuna.
        #expect(r.first { $0.id == "volkswagen-tiguan" }?.image == nil)
    }

    @Test func altraVersione() {
        let cards = [card("Volkswagen", "Golf Variant 1.6 TDI", rarity: .rara)]
        let matches = AlbumMatches(cards: cards, matcher: matcher)
        let r = AlbumBuilder.build(index: index, matches: matches, filters: AlbumFilters(), now: now)
        #expect(r.stats.modelsFound == 1)
        #expect(entries(r).first { $0.id == "volkswagen-golf" }?.isFound == true)

        let rows = AlbumBuilder.variantRows(modelId: "volkswagen-golf", index: index, matches: matches)
        #expect(rows.first?.id == "volkswagen-golf")
        #expect(rows.first?.isFound == false)
        #expect(rows.filter { !$0.isOtherVersion }.count == 3)
        let other = rows.last
        #expect(other?.isOtherVersion == true)
        #expect(other?.isFound == true)
        #expect(other?.rarity == .rara)
        #expect(other?.cardIDs == [cards[0].id])
    }

    @Test func righeVersioneTrovata() {
        let cards = [card("VW", "Golf GTI", rarity: .epica), card("VW", "Golf GTI", rarity: .rara)]
        let matches = AlbumMatches(cards: cards, matcher: matcher)
        let rows = AlbumBuilder.variantRows(modelId: "volkswagen-golf", index: index, matches: matches)
        let gti = rows.first { $0.id == "volkswagen-golf-gti" }
        #expect(gti?.copies == 2)
        #expect(gti?.rarity == .epica)
        // Versione senza immagine propria: usa quella del modello.
        #expect(gti?.image?.path == "x/volkswagen-golf.webp")
        #expect(rows.first { $0.id == "volkswagen-golf-r" }?.isFound == false)
    }

    @Test func orfaniInFondoAllaMarca() {
        let orphan = card("Fiat", "Zzz")
        let lost = card("Marca Ignota", "X")
        let r = build([orphan, lost])
        #expect(r.sections.first { $0.id == "fiat" }?.orphans.map(\.id) == [orphan.id])
        #expect(r.sections.last?.id == AlbumBuilder.uncatalogedID)
        #expect(r.sections.last?.orphans.map(\.id) == [lost.id])
        // Non contano nei progressi.
        #expect(r.stats == AlbumStats())
        #expect(r.sections.first { $0.id == "fiat" }?.found == 0)
    }

    @Test func orfaniNascostiConPillola() {
        let cards = [card("Fiat", "Zzz"), card("Marca Ignota", "X")]
        #expect(build(cards, AlbumFilters(bodyType: .utilitaria)).sections.allSatisfy { $0.orphans.isEmpty })
        #expect(build(cards, AlbumFilters(ownership: .missing)).sections.allSatisfy { $0.orphans.isEmpty })
        // La ricerca per nome li trova, la pillola no.
        let byName = build(cards, AlbumFilters(query: "zzz"))
        #expect(byName.sections.first { $0.id == "fiat" }?.orphans.count == 1)
        #expect(byName.sections.contains { $0.id == AlbumBuilder.uncatalogedID } == false)
        let both = build(cards, AlbumFilters(rarity: .comune, query: "zzz"))
        #expect(both.sections.allSatisfy { $0.orphans.isEmpty })
    }

    @Test func isNarrowed() {
        #expect(!AlbumFilters().isNarrowed)
        #expect(!AlbumFilters(ownership: .found).isNarrowed)
        #expect(!AlbumFilters(query: "  ").isNarrowed)
        #expect(AlbumFilters(query: "fiat").isNarrowed)
        #expect(AlbumFilters(era: 1970).isNarrowed)
    }

    @Test func omonimiConAnnoNelNome() {
        let names = entries(build([])).filter { $0.makeName == "Fiat" }.map(\.name)
        #expect(names.contains("500 (1957)"))
        #expect(names.contains("500 (2007)"))
        #expect(names.contains("Panda"))
    }
}
