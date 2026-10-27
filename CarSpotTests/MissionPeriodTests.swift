import Testing
import Foundation
@testable import CarSpot

/// Periodi delle missioni (calendario di Roma) e generatore con seme stabile.
struct MissionPeriodTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func settimanaDaLunedi() {
        let period = MissionPeriod.containing(date(2026, 10, 29, 15), kind: .week, calendar: calendar)
        #expect(period.startKey == "2026-10-26")
        #expect(period.start == date(2026, 10, 26))
        #expect(period.end == date(2026, 11, 2))
    }

    @Test func settimanaConCambioOra() {
        // Il 25 ottobre 2026 si torna all'ora solare: la settimana ha 7 giorni, non 168 h.
        let period = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .week, calendar: calendar)
        #expect(period.startKey == "2026-10-19")
        #expect(period.end == date(2026, 10, 26))
        #expect(period.end.timeIntervalSince(period.start) == 7 * 86_400 + 3_600)
    }

    @Test func meseDalPrimo() {
        let period = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .month, calendar: calendar)
        #expect(period.startKey == "2026-10-01")
        #expect(period.end == date(2026, 11, 1))
        #expect(period.previous(calendar: calendar).startKey == "2026-09-01")
    }

    @Test func meseOttobreConCambioOra() {
        // Ottobre 2026 a Roma ha il giorno da 25 ore (25 ottobre): 31 giorni + 1 ora.
        let period = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .month, calendar: calendar)
        #expect(period.end.timeIntervalSince(period.start) == (31 * 24 + 1) * 3600)
        #expect(period.end == date(2026, 11, 1))
    }

    @Test func periodoPrecedente() {
        let day = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .day, calendar: calendar)
        #expect(day.previous(calendar: calendar).startKey == "2026-10-24")
        let week = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .week, calendar: calendar)
        #expect(week.previous(calendar: calendar).startKey == "2026-10-12")
    }

    @Test func scadenzaDueGiorni() {
        let period = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .day, calendar: calendar)
        #expect(period.claimDeadline == date(2026, 10, 28))
    }

    @Test func comuneDateIncluse() throws {
        let period = try #require(MissionPeriod.community(startsOn: "2026-11-01", endsOn: "2026-11-30", calendar: calendar))
        #expect(period.kind == .community)
        #expect(period.start == date(2026, 11, 1))
        #expect(period.end == date(2026, 12, 1))
        #expect(MissionPeriod.community(startsOn: "domani", endsOn: "2026-11-30", calendar: calendar) == nil)
        #expect(MissionPeriod.community(startsOn: "2026-11-30", endsOn: "2026-11-01", calendar: calendar) == nil)
    }

    @Test func identita() {
        let period = MissionPeriod.containing(date(2026, 10, 25, 12), kind: .week, calendar: calendar)
        #expect(period.identity("w_makes") == "week:2026-10-19|w_makes")
    }

    @Test func seedStabile() {
        var a = StableRandom(seed: "u|week|2026-10-19")
        var b = StableRandom(seed: "u|week|2026-10-19")
        let first = (0..<5).map { _ in a.next() }
        let second = (0..<5).map { _ in b.next() }
        #expect(first == second)
        var other = StableRandom(seed: "v|week|2026-10-19")
        #expect(other.next() != first[0])
    }
}
