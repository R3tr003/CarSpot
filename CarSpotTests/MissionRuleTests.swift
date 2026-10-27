import Testing
import Foundation
@testable import CarSpot

/// Regola-dati delle missioni: finestra, ripetizioni, liste bersaglio, "nuovo", JSON.
struct MissionRuleTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    /// Giorno di riferimento: 2026-10-20 (nessun cambio d'ora).
    private var dayStart: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))! }
    private var dayEnd: Date { calendar.date(byAdding: .day, value: 1, to: dayStart)! }
    private var noon: Date { dayStart.addingTimeInterval(12 * 3_600) }

    private func card(_ make: String = "Fiat", _ model: String = "Panda", year: Int = 0,
                      rarity: Rarity = .comune, area: String = "", at date: Date,
                      isRepeat: Bool = false) -> MissionCard {
        MissionCard(make: make, model: model, year: year, rarity: rarity, area: area,
                    capturedAt: date, isRepeat: isRepeat)
    }

    @Test func normGemellaDelServer() {
        #expect(MissionText.norm("  Alfa   Romeo ") == "alfa romeo")
    }

    @Test func contaSoloNellaFinestra() {
        let cards = [
            card(at: dayStart.addingTimeInterval(-12 * 3_600)),
            card(at: noon),
            card(at: dayEnd.addingTimeInterval(12 * 3_600)),
        ]
        #expect(MissionRule().progress(cards: cards, from: dayStart, to: dayEnd) == 1)
    }

    @Test func escludeRipetizioni() {
        let cards = [card(at: noon), card(at: noon, isRepeat: true)]
        #expect(MissionRule().progress(cards: cards, from: dayStart, to: dayEnd) == 1)
    }

    @Test func rarMinima() {
        let cards = Rarity.allCases.map { card(rarity: $0, at: noon) }
        let rule = MissionRule(count: .cards, minRarity: .epica)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 2)
    }

    @Test func annoZeroNonConta() {
        let cards = [0, 1985, 1995].map { card(year: $0, at: noon) }
        let rule = MissionRule(count: .cards, yearTo: 1989)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 1)
    }

    @Test func listaBersaglioPrefisso() {
        let cards = [
            card("Porsche", "911 Carrera", at: noon),
            card("Porsche", "911", at: noon),
            card("Porsche", "9110", at: noon),
        ]
        let rule = MissionRule(count: .cards, models: ["porsche|911"])
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 2)
    }

    @Test func stessaAutoContaUnaVoltaPerModelli() {
        let cards = [
            card("VW", "Golf GTI", at: noon),
            card("vw", "golf gti", at: noon),
            card("Fiat", "Panda", at: noon),
        ]
        let rule = MissionRule(count: .models)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 2)
    }

    @Test func areeVuoteNonContano() {
        let cards = ["Brera", " brera", "", "Isola"].map { card(area: $0, at: noon) }
        let rule = MissionRule(count: .areas)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 2)
    }

    @Test func freshArea() {
        let cards = [
            card(area: "Brera", at: dayStart.addingTimeInterval(-86_400)),
            card(area: "Brera", at: noon),
            card(area: "Isola", at: noon),
        ]
        let rule = MissionRule(count: .cards, fresh: .area)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 1)
    }

    @Test func freshModelConCountModels() {
        let cards = [
            card("VW", "Golf GTI", at: dayStart.addingTimeInterval(-86_400)),
            card("VW", "Golf GTI", at: noon),
            card("Fiat", "Panda", at: noon),
            card("Fiat", "Panda", at: noon.addingTimeInterval(60)),
        ]
        let rule = MissionRule(count: .models, fresh: .model)
        #expect(rule.progress(cards: cards, from: dayStart, to: dayEnd) == 1)
    }

    @Test func jsonSnakeCase() throws {
        let rule = MissionRule(count: .cards, minRarity: .rara, yearTo: 1989)
        let data = try JSONEncoder().encode(rule)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"min_rarity\":\"Rara\""))
        #expect(json.contains("\"year_to\":1989"))
        #expect(!json.contains("\"makes\""))
        #expect(try JSONDecoder().decode(MissionRule.self, from: data) == rule)
    }
}
