import Testing
import Foundation
@testable import CarSpot

/// Catalogo di prova condiviso dai test (5 marche, 10 modelli, 13 versioni).
enum TestCatalog {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static func make(_ id: String, _ name: String, _ country: String?, aliases: [String] = []) -> CatalogMake {
        CatalogMake(id: id, name: name, country: country, aliases: aliases, updatedAt: date)
    }

    static func model(_ id: String, _ makeId: String, _ name: String, _ body: BodyType,
                      _ start: Int?, _ end: Int? = nil, pop: Int = 50, aliases: [String] = []) -> CatalogModel {
        CatalogModel(id: id, makeId: makeId, name: name, bodyType: body, yearStart: start, yearEnd: end,
                     popularity: pop, aliases: aliases, updatedAt: date)
    }

    static func variant(_ id: String, _ modelId: String, _ name: String, base: Bool = false,
                        _ start: Int? = nil, image: CatalogImage? = nil) -> CatalogVariant {
        CatalogVariant(id: id, modelId: modelId, name: name, isBase: base, yearStart: start, yearEnd: nil,
                       aliases: [], updatedAt: date, image: image)
    }

    static func image(_ path: String) -> CatalogImage {
        CatalogImage(path: path, width: 512, height: 300, title: "File:x.jpg", author: "Autore",
                     license: "CC BY 4.0", licenseURL: nil, sourceURL: nil, modified: true)
    }

    static let snapshot: CatalogSnapshot = {
        let models = [
            model("alfa-romeo-giulia", "alfa-romeo", "Giulia", .berlina, 2015, pop: 70),
            model("citroen-c3", "citroen", "C3", .utilitaria, 2002, pop: 60),
            model("ferrari-f8", "ferrari", "F8 Tributo", .sportiva, 2019, 2023, pop: 50),
            model("ferrari-250-gto", "ferrari", "250 GTO", .sportiva, 1962, 1964, pop: 90),
            model("fiat-500", "fiat", "500", .utilitaria, 2007, pop: 90),
            model("fiat-500-1957", "fiat", "500", .utilitaria, 1957, 1975, pop: 80),
            model("fiat-panda", "fiat", "Panda", .utilitaria, 1980, pop: 85),
            model("fiat-doblo", "fiat", "Doblò", .monovolume, 2000, pop: 40, aliases: ["Doblo"]),
            model("volkswagen-golf", "volkswagen", "Golf", .berlina, 1974, pop: 95),
            model("volkswagen-tiguan", "volkswagen", "Tiguan", .suv, 2007, pop: 60),
        ]
        // Ogni modello ha la base; alcune hanno un'immagine.
        let withImage: Set<String> = ["fiat-500", "volkswagen-golf", "alfa-romeo-giulia"]
        var variants = models.map {
            variant($0.id, $0.id, $0.name, base: true, $0.yearStart,
                    image: withImage.contains($0.id) ? image("x/\($0.id).webp") : nil)
        }
        variants += [
            variant("alfa-romeo-giulia-quadrifoglio", "alfa-romeo-giulia", "Giulia Quadrifoglio", 2016),
            variant("volkswagen-golf-gti", "volkswagen-golf", "Golf GTI", 1976),
            variant("volkswagen-golf-r", "volkswagen-golf", "Golf R", 2004),
        ]
        return CatalogSnapshot(
            version: 1, generatedAt: date,
            imageBaseURL: URL(string: "https://example.com/car-models/")!,
            makes: [
                make("alfa-romeo", "Alfa Romeo", "IT", aliases: ["Alfa"]),
                make("citroen", "Citroën", "FR"),
                make("ferrari", "Ferrari", "IT"),
                make("fiat", "Fiat", "IT", aliases: ["FIAT"]),
                make("volkswagen", "Volkswagen", "DE", aliases: ["VW"]),
            ],
            models: models, variants: variants
        )
    }()

    static let index = CatalogIndex(snapshot)
    static let matcher = CatalogMatcher(index: index)
}

/// Abbinamento carta salvata -> catalogo.
struct CatalogMatcherTests {
    private let matcher = TestCatalog.matcher

    @Test func marcaAlias() {
        #expect(matcher.match(make: "VW", model: "Golf GTI", year: 2019) == .variant(id: "volkswagen-golf-gti"))
        #expect(matcher.match(make: "vw", model: "golf  gti", year: 2019) == .variant(id: "volkswagen-golf-gti"))
        #expect(matcher.match(make: "Alfa-Romeo", model: "Giulia", year: 2020) == .variant(id: "alfa-romeo-giulia"))
        #expect(matcher.match(make: "Alfa", model: "Giulia Quadrifoglio", year: 2020)
                == .variant(id: "alfa-romeo-giulia-quadrifoglio"))
    }

    @Test func diacritici() {
        #expect(matcher.match(make: "Citroen", model: "C3", year: 2018) == .variant(id: "citroen-c3"))
        #expect(matcher.match(make: "Citroën", model: "c3", year: 2018) == .variant(id: "citroen-c3"))
        #expect(matcher.match(make: "Fiat", model: "Doblo", year: 2012) == .variant(id: "fiat-doblo"))
    }

    @Test func prefisso() {
        #expect(matcher.match(make: "Volkswagen", model: "Golf Variant 1.6 TDI", year: 2016)
                == .otherVersion(modelId: "volkswagen-golf"))
        // Il prefisso deve finire a fine parola.
        #expect(matcher.match(make: "Volkswagen", model: "Golfino", year: 2016) == .unmatched(makeId: "volkswagen"))
    }

    @Test func omonimiPerAnno() {
        #expect(matcher.match(make: "Fiat", model: "500", year: 1968) == .variant(id: "fiat-500-1957"))
        #expect(matcher.match(make: "Fiat", model: "500", year: 2015) == .variant(id: "fiat-500"))
        #expect(matcher.match(make: "Fiat", model: "500 Abarth", year: 1968) == .otherVersion(modelId: "fiat-500-1957"))
        #expect(matcher.match(make: "Fiat", model: "500 Abarth", year: 2015) == .otherVersion(modelId: "fiat-500"))
    }

    @Test func fuoriCatalogo() {
        #expect(matcher.match(make: "Fiat", model: "Zzz", year: 2010) == .unmatched(makeId: "fiat"))
        #expect(matcher.match(make: "Marca Ignota", model: "X", year: 2010) == .unmatched(makeId: nil))
        #expect(matcher.match(make: "Fiat", model: "  ", year: 2010) == .unmatched(makeId: "fiat"))
    }
}
