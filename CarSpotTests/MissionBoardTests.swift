import Testing
import Foundation
@testable import CarSpot

/// Tabellone delle missioni (segmenti, avanzi, pallini) e missioni comuni.
struct MissionBoardTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Giovedì 23 ottobre 2026, mezzogiorno.
    private var now: Date { date(23, 12) }

    private func card(at when: Date, make: String = "Fiat", model: String = "Panda") -> MissionCard {
        MissionCard(make: make, model: model, capturedAt: when)
    }

    private func build(cards: [MissionCard] = [], claimed: Set<String> = [], seen: Set<String> = [],
                       community: [CommunityMission] = [], region: String? = "IT",
                       now: Date? = nil) -> [MissionSegment] {
        MissionBoard.build(cards: cards, ownerId: "", claimed: claimed, seen: seen, community: community,
                           region: region, now: now ?? self.now, calendar: calendar)
    }

    private func community(_ id: String, scope: String, from: String = "2026-10-01", to: String = "2026-10-31",
                           goal: Int = 1) -> CommunityMission {
        CommunityMission(id: id, scope: scope, titleIt: "Titolo \(id)", titleEn: "Title \(id)",
                         startsOn: from, endsOn: to, rule: MissionRule(), goal: goal, reward: 500,
                         badgeId: "community:\(id)")
    }

    @Test func quattroSegmentiInOrdine() {
        let segments = build()
        #expect(segments.map(\.kind) == [.day, .week, .month, .community])
        #expect(segments[0].current.count == 3)
        #expect(segments[1].current.count == 3)
        #expect(segments[2].current.count == 2)
        #expect(segments[3].current.isEmpty)
        #expect(segments[3].endsAt == nil)
        #expect(segments[0].endsAt == date(24, 0))
    }

    @Test func progressoSoloNelPeriodo() throws {
        let yesterday = card(at: date(22, 12))
        let day = try #require(build(cards: [yesterday]).first)
        let volume = try #require(day.current.first { $0.mission.missionId == "d_cards" })
        #expect(volume.progress == 0)
        #expect(!volume.done)
    }

    @Test func riscattatoDaIdentita() throws {
        let today = card(at: date(23, 10))
        let first = try #require(build(cards: [today]).first?.current.first { $0.mission.missionId == "d_cards" })
        #expect(first.claimable)
        #expect(first.progress == first.mission.goal)

        let after = try #require(build(cards: [today], claimed: [first.mission.id]).first?
            .current.first { $0.mission.missionId == "d_cards" })
        #expect(after.claimed)
        #expect(!after.claimable)
        #expect(!after.isNew)
    }

    @Test func avanziEntroDueGiorni() throws {
        // Missione del 22 ottobre completata e mai riscattata.
        let cards = [card(at: date(22, 10))]

        func leftoverDays(_ at: Date) -> [String] {
            build(cards: cards, now: at).first?.leftovers
                .filter { $0.mission.missionId == "d_cards" }
                .map { $0.mission.period.startKey } ?? []
        }
        #expect(leftoverDays(date(23, 12)) == ["2026-10-22"])
        #expect(leftoverDays(date(24, 12)) == ["2026-10-22"])
        // Dal 25 la finestra (fine + 2 giorni = 25 00:00) è chiusa.
        #expect(leftoverDays(date(25, 12)).isEmpty)
    }

    @Test func avanziRiscattatiSpariscono() throws {
        let cards = [card(at: date(22, 10))]
        let leftover = try #require(build(cards: cards).first?.leftovers.first { $0.mission.missionId == "d_cards" })
        let day = try #require(build(cards: cards, claimed: [leftover.mission.id]).first)
        #expect(!day.leftovers.contains { $0.mission.id == leftover.mission.id })
    }

    @Test func contatoriPallini() throws {
        let today = card(at: date(23, 10))
        let before = try #require(build(cards: [today]).first)
        let volume = try #require(before.current.first { $0.mission.missionId == "d_cards" })
        #expect(volume.claimable)
        #expect(before.newCount == before.current.count)

        // Tutte riscattate tranne il volume, che resta da riscattare; il volume è già stato visto.
        let others = Set(before.current.filter(\.claimable).map(\.id)).subtracting([volume.id])
        let day = try #require(build(cards: [today], claimed: others, seen: [volume.id]).first)
        #expect(day.claimableCount == 1)
        #expect(day.newCount == day.current.filter { $0.id != volume.id && !others.contains($0.id) }.count)
        #expect(day.newCount <= 2)
    }

    @Test func comuniPerRegione() {
        let missions = [
            community("c_world", scope: "world"),
            community("c_europe", scope: "europe"),
            community("c_it", scope: "IT"),
            community("c_fr", scope: "FR"),
        ]
        func ids(_ region: String?) -> Set<String> {
            Set(build(community: missions, region: region)[3].current.map(\.mission.missionId))
        }
        #expect(ids("IT") == ["c_world", "c_europe", "c_it"])
        #expect(ids("FR") == ["c_world", "c_europe", "c_fr"])
        #expect(ids("US") == ["c_world"])
        #expect(ids(nil) == ["c_world"])
    }

    @Test func comuneNonIniziataEScaduta() throws {
        let future = community("c_future", scope: "world", from: "2026-10-24", to: "2026-10-31")
        #expect(build(community: [future])[3].current.isEmpty)

        // Finita da 3 giorni (ieri + 2 giorni di grazia già passati): assente.
        let old = community("c_old", scope: "world", from: "2026-10-01", to: "2026-10-20")
        let cards = [card(at: date(19, 12))]
        let expired = build(cards: cards, community: [old])[3]
        #expect(expired.current.isEmpty)
        #expect(expired.leftovers.isEmpty)

        // Finita ieri e completata: resta da riscattare.
        let recent = community("c_recent", scope: "world", from: "2026-10-01", to: "2026-10-22")
        let segment = build(cards: [card(at: date(22, 10))], community: [recent])[3]
        #expect(segment.current.isEmpty)
        #expect(segment.leftovers.map(\.mission.missionId) == ["c_recent"])
        #expect(segment.claimableCount == 1)
    }

    @Test func comuneDecodificaJSON() throws {
        let json = """
        {"id":"c1","scope":"IT","title_it":"Piccole cattive italiane","title_en":"Little Italian bruisers",
         "starts_on":"2026-10-26","ends_on":"2026-11-30",
         "rule":{"count":"models","models":["abarth|595","fiat|panda 100hp"]},
         "goal":1,"reward":600,"badge_id":"community:2026-11-it-hothatch"}
        """
        let mission = try JSONDecoder().decode(CommunityMission.self, from: Data(json.utf8))
        #expect(mission.id == "c1")
        #expect(mission.titleIt == "Piccole cattive italiane")
        #expect(mission.rule.count == .models)
        #expect(mission.rule.models == ["abarth|595", "fiat|panda 100hp"])
        #expect(mission.badgeId == "community:2026-11-it-hothatch")

        let ready = try #require(mission.mission(calendar: calendar))
        #expect(ready.id == "community:2026-10-26|c1")
        #expect(ready.source == .community(scope: "IT"))
        #expect(ready.badgeId == "community:2026-11-it-hothatch")
        #expect(ready.period.end == date(1, 0, month: 12))

        // Senza badge_id e con date non valide.
        let bare = #"{"id":"c2","scope":"world","title_it":"A","title_en":"B","starts_on":"x","ends_on":"y","rule":{},"goal":2,"reward":10}"#
        let invalid = try JSONDecoder().decode(CommunityMission.self, from: Data(bare.utf8))
        #expect(invalid.badgeId == nil)
        #expect(invalid.rule.count == .cards)
        #expect(invalid.mission(calendar: calendar) == nil)
    }
}
