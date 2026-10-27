import Testing
import Foundation
@testable import CarSpot

/// Repertorio e generatore delle missioni personali.
struct MissionEngineTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! }

    private func period(_ kind: MissionPeriodKind) -> MissionPeriod {
        MissionPeriod.containing(now, kind: kind, calendar: calendar)
    }

    private func generate(_ kind: MissionPeriodKind, owner: String = "owner", cards: [MissionCard] = []) -> [Mission] {
        MissionEngine.personal(for: period(kind), ownerId: owner, cards: cards, calendar: calendar)
    }

    /// `count` carte nei giorni prima di `start`, con marche e modelli diversi.
    private func past(_ count: Int, before start: Date, rarity: (Int) -> Rarity = { _ in .comune },
                      make: (Int) -> String = { "Marca\($0)" }, year: Int = 2015) -> [MissionCard] {
        (0..<count).map { i in
            let when = calendar.date(byAdding: .day, value: -(1 + i % 20), to: start)!
            return MissionCard(make: make(i), model: "Modello\(i)", year: year, rarity: rarity(i),
                               area: "Brera", capturedAt: when)
        }
    }

    @Test func poolCompleto() {
        let pool = MissionCatalog.pool
        #expect(pool.filter { $0.kind == .day }.count == 8)
        #expect(pool.filter { $0.kind == .week }.count == 9)
        #expect(pool.filter { $0.kind == .month }.count == 9)
        #expect(Set(pool.map(\.id)).count == pool.count)
        #expect(MissionCatalog.template(id: "w_make") != nil)
        #expect(MissionCatalog.template(id: "inesistente") == nil)
    }

    @Test func premioFormula() throws {
        let weekly = try #require(MissionCatalog.template(id: "w_cards"))
        #expect(weekly.reward(goal: 40) == 500)
        #expect(weekly.reward(goal: 5) == 200)
        #expect(try #require(MissionCatalog.template(id: "m_list_icons")).reward(goal: 1) == 1000)
        #expect(try #require(MissionCatalog.template(id: "d_epic")).reward(goal: 1) == 130)
    }

    @Test func obiettiviDelRepertorio() throws {
        let cards = try #require(MissionCatalog.template(id: "d_cards"))
        #expect(cards.goal(for: .occasional) == 1)
        #expect(cards.goal(for: .regular) == 3)
        #expect(cards.goal(for: .hunter) == 6)
    }

    @Test func titoloSingolareEPlurale() throws {
        let cards = try #require(MissionCatalog.template(id: "d_cards"))
        #expect(cards.title(goal: 1, params: nil) != cards.title(goal: 3, params: nil))
        #expect(cards.title(goal: 3, params: nil).contains("3"))
    }

    @Test func deterministico() {
        for kind in [MissionPeriodKind.day, .week, .month] {
            #expect(generate(kind).map(\.id) == generate(kind).map(\.id))
        }
    }

    @Test func quantitaPerPeriodo() {
        let expected: [(MissionPeriodKind, Int)] = [(.day, 3), (.week, 3), (.month, 2)]
        for (kind, count) in expected {
            let missions = generate(kind)
            #expect(missions.count == count)
            #expect(Set(missions.map(\.missionId)).count == count)
        }
        #expect(generate(.community).isEmpty)
    }

    @Test func slotRispettati() throws {
        let day = generate(.day)
        #expect(day.first?.missionId == "d_cards")
        #expect(day.allSatisfy { $0.badgeId == nil })

        let week = generate(.week)
        #expect(week.first?.missionId == "w_cards")

        let month = generate(.month)
        let first = try #require(month.first)
        #expect(MissionCatalog.template(id: first.missionId)?.slot == .list)
        #expect(first.badgeId == "month:2026-10|\(first.missionId)")
        #expect(first.id == "month:2026-10-01|\(first.missionId)")
    }

    @Test func obiettivoDalRitmo() throws {
        let start = period(.day).start
        let hunter = past(80, before: start)
        let missions = generate(.day, cards: hunter)
        let volume = try #require(missions.first { $0.missionId == "d_cards" })
        #expect(volume.goal == 6)
        #expect(volume.reward == 160)
        #expect(volume.title == MissionCatalog.template(id: "d_cards")!.title(goal: 6, params: nil))
    }

    @Test func carteNelPeriodoNonCambianoLeMissioni() {
        let week = period(.week)
        let before = past(30, before: week.start)
        let during = (0..<50).map { i in
            MissionCard(make: "Ferrari\(i)", model: "F40", year: 1990, rarity: .leggendaria,
                        area: "Zona\(i)", capturedAt: week.start.addingTimeInterval(Double(i + 1) * 600))
        }
        let a = generate(.week, cards: before).map(\.id)
        let b = generate(.week, cards: before + during).map(\.id)
        #expect(a == b)
    }

    @Test func parametroMarca() throws {
        let week = period(.week)
        let porsche = past(12, before: week.start, make: { _ in "Porsche" })
        // Il modello esce a seconda del seme: cerco un giocatore a cui capita.
        var found: Mission?
        for owner in 0..<100 where found == nil {
            let missions = generate(.week, owner: "o\(owner)", cards: porsche)
            found = missions.first { $0.missionId == "w_make" }
        }
        let mission = try #require(found)
        #expect(mission.params?.make == "Porsche")
        #expect(mission.rule.makes == ["porsche"])
        let template = try #require(MissionCatalog.template(id: "w_make"))
        #expect(mission.rule == template.rule(with: mission.params))
    }

    @Test func parametroDecennio() throws {
        let template = try #require(MissionCatalog.template(id: "w_decade"))
        let rule = template.rule(with: MissionParams(decade: 1970))
        #expect(rule.yearFrom == 1970)
        #expect(rule.yearTo == 1979)
        let week = period(.week)
        let seventies = past(12, before: week.start, year: 1975)
        for owner in 0..<40 {
            let missions = generate(.week, owner: "o\(owner)", cards: seventies)
            if let decade = missions.first(where: { $0.missionId == "w_decade" })?.params?.decade {
                #expect(decade != 1970)
                #expect(decade % 10 == 0 && (1950...2010).contains(decade))
            }
        }
    }

    @Test func stileFavorito() {
        let week = period(.week)
        let rarityPlayer = past(10, before: week.start, rarity: { $0 < 3 ? .epica : .comune })
        let generalist = past(10, before: week.start)

        func rareCount(_ cards: [MissionCard]) -> Int {
            (0..<200).filter { owner in
                generate(.week, owner: "u\(owner)", cards: cards)
                    .contains { $0.missionId == "w_rare" || $0.missionId == "w_epic" }
            }.count
        }
        #expect(rareCount(rarityPlayer) > rareCount(generalist))
    }
}
