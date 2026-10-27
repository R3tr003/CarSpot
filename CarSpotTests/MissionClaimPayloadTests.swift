import Testing
import Foundation
@testable import CarSpot

/// Payload del riscatto in coda e riga `mission_claims` inviata al cloud.
struct MissionClaimPayloadTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func mission() -> Mission {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let period = MissionPeriod.containing(day, kind: .week, calendar: calendar)
        return Mission(
            id: period.identity("w_makes"), missionId: "w_makes", period: period, source: .personal,
            icon: "car", title: "Tre marchi diversi", rule: MissionRule(count: .makes),
            goal: 3, reward: 90, params: MissionParams(make: "Fiat"), badgeId: nil)
    }

    @Test func finestraDalPeriodo() {
        let mission = mission()
        let payload = MissionClaimPayload(mission)
        #expect(payload.windowStart == mission.period.start)
        #expect(payload.windowEnd == mission.period.end)
        #expect(payload.deadline == mission.period.claimDeadline)
        #expect(payload.reward == 90)
        #expect(payload.title == "Tre marchi diversi")
    }

    @Test func jsonVecchioSiLegge() throws {
        let data = try JSONEncoder().encode(MissionClaimPayload(mission()))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["windowEnd", "reward", "title"] { object.removeValue(forKey: key) }
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MissionClaimPayload.self, from: old)
        #expect(decoded.windowEnd == nil)
        #expect(decoded.reward == nil)
        #expect(decoded.title == nil)
        #expect(decoded.identity == mission().id)
    }

    @Test func cloudClaimHaWindowEnd() throws {
        let claim = CloudMissionClaim(MissionClaimPayload(mission()))
        let data = try JSONEncoder().encode(claim)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["window_end"] != nil)
        #expect(object["window_start"] != nil)
    }
}
