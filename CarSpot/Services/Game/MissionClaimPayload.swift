import Foundation

/// Riscatto in coda per il cloud: tutto quello che serve a inviarlo, scartarlo se scaduto
/// o annullarlo se il server lo rifiuta. Salvato come JSON in `pendingMissionClaims`.
struct MissionClaimPayload: Codable, Sendable, Hashable {
    /// `Mission.id`: chiave locale del riscatto.
    let identity: String
    let period: MissionPeriodKind
    /// "yyyy-MM-dd" del primo giorno del periodo.
    let periodStart: String
    let missionId: String
    let goal: Int
    let params: MissionParams?
    /// Istante di inizio del periodo all'ora del telefono.
    let windowStart: Date
    /// Oltre questa data il riscatto è perso (fine periodo + 2 giorni).
    let deadline: Date
    let badgeId: String?
    /// Fine (esclusa) del periodo all'ora del telefono. Opzionale: la coda di versioni
    /// precedenti non la contiene.
    let windowEnd: Date?
    /// Premio e titolo, per annullare il riscatto in locale se il server lo rifiuta.
    let reward: Int?
    let title: String?

    init(_ mission: Mission) {
        identity = mission.id
        period = mission.period.kind
        periodStart = mission.period.startKey
        missionId = mission.missionId
        goal = mission.goal
        params = mission.params
        windowStart = mission.period.start
        deadline = mission.period.claimDeadline
        badgeId = mission.badgeId
        windowEnd = mission.period.end
        reward = mission.reward
        title = mission.title
    }
}
