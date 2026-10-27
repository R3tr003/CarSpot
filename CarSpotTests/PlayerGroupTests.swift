import Testing
import Foundation
@testable import CarSpot

/// Gruppo del giocatore: ritmo dalle ultime 4 settimane, stile dalla collezione.
struct PlayerGroupTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    /// Inizio del periodo: 2026-10-19.
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))! }

    /// Carta catturata `daysAgo` giorni prima di `start` (almeno 1).
    private func card(_ make: String = "Fiat", _ model: String = "Panda", year: Int = 2015,
                      rarity: Rarity = .comune, area: String = "Brera", daysAgo: Int = 3) -> MissionCard {
        let when = calendar.date(byAdding: .day, value: -daysAgo, to: start)!
        return MissionCard(make: make, model: model, year: year, rarity: rarity, area: area, capturedAt: when)
    }

    private func many(_ count: Int, daysAgo: Int = 3) -> [MissionCard] {
        (0..<count).map { card("Marca\($0)", "Modello\($0)", daysAgo: daysAgo) }
    }

    @Test func nessunaCartaOccasionale() {
        let group = PlayerGroup.compute(cards: [], before: start, calendar: calendar)
        #expect(group.pace == .occasional)
        #expect(group.style == .generalist)
    }

    @Test func ritmoAbituale() {
        // 24 carte in 28 giorni = 6 a settimana.
        let group = PlayerGroup.compute(cards: many(24), before: start, calendar: calendar)
        #expect(group.pace == .regular)
    }

    @Test func ritmoCacciatore() {
        // 80 carte in 28 giorni = 20 a settimana.
        let group = PlayerGroup.compute(cards: many(80), before: start, calendar: calendar)
        #expect(group.pace == .hunter)
    }

    @Test func carteDentroIlPeriodoIgnorate() {
        let inside = (0..<80).map { i in
            MissionCard(make: "Marca\(i)", model: "M", capturedAt: start.addingTimeInterval(Double(i + 1) * 60))
        }
        let group = PlayerGroup.compute(cards: inside, before: start, calendar: calendar)
        #expect(group.pace == .occasional)
        #expect(group.style == .generalist)
    }

    @Test func ripetizioniIgnorate() {
        var cards = many(24)
        for i in cards.indices { cards[i].isRepeat = true }
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).pace == .occasional)
    }

    @Test func stileRarita() {
        var cards = many(8)
        cards.append(card("Ferrari", "F40", rarity: .epica))
        cards.append(card("Lamborghini", "Countach", rarity: .epica))
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).style == .rarity)
    }

    @Test func stileEpocaBatteMarca() {
        // Dieci Fiat anni '70: epoca 1.0/0.3 batte marca 1.0/0.4.
        let cards = (0..<10).map { card("Fiat", "Modello\($0)", year: 1975) }
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).style == .vintage)
    }

    @Test func stileMarca() {
        let cards = (0..<10).map { card("Fiat", "Modello\($0)") }
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).style == .brand)
    }

    @Test func stileEsploratore() {
        let cards = (0..<10).map { card("Marca\($0)", "M", area: "Zona\($0 % 6)") }
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).style == .explorer)
    }

    @Test func menoDiDieciGeneralista() {
        let cards = (0..<9).map { card("Fiat", "Modello\($0)", year: 1975, rarity: .leggendaria) }
        #expect(PlayerGroup.compute(cards: cards, before: start, calendar: calendar).style == .generalist)
    }
}
