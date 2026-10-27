import Foundation
import os

private let communityLog = Logger(subsystem: "com.carspot.andrea.app", category: "community")

/// Missione comune: scritta a mano sul server (tabella `community_missions`), uguale per
/// tutti in un ambito, con barra personale.
struct CommunityMission: Codable, Sendable, Hashable, Identifiable {
    let id: String
    /// "world" | "europe" | codice Paese ISO ("IT").
    let scope: String
    let titleIt: String
    let titleEn: String
    /// Date incluse, "yyyy-MM-dd".
    let startsOn: String
    let endsOn: String
    let rule: MissionRule
    let goal: Int
    let reward: Int
    let badgeId: String?

    enum CodingKeys: String, CodingKey {
        case id, scope
        case titleIt = "title_it"
        case titleEn = "title_en"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case rule, goal, reward
        case badgeId = "badge_id"
    }

    /// Regioni considerate "Europa": UE, SEE, Regno Unito, Svizzera e altri Paesi europei.
    static let europeanRegions: Set<String> = [
        // UE
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
        "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        // SEE
        "NO", "IS", "LI",
        // Altri
        "GB", "CH", "AL", "BA", "ME", "MK", "RS", "MD", "UA", "AD", "MC", "SM", "VA",
    ]

    /// Mondo sempre; Europa se la regione del telefono è europea; altrimenti il Paese deve coincidere.
    func isVisible(region: String?) -> Bool {
        let code = scope.uppercased()
        if code == "WORLD" { return true }
        guard let region = region?.uppercased() else { return false }
        if code == "EUROPE" { return Self.europeanRegions.contains(region) }
        return code == region
    }

    /// Missione pronta per il tabellone; nil se le date, l'obiettivo o la ricompensa non sono validi.
    func mission(calendar: Calendar) -> Mission? {
        guard goal > 0, reward > 0 else { return nil }
        guard let period = MissionPeriod.community(startsOn: startsOn, endsOn: endsOn, calendar: calendar) else {
            return nil
        }
        let english = Locale.app.identifier.hasPrefix("en")
        let preferred = english ? titleEn : titleIt
        let fallback = english ? titleIt : titleEn
        return Mission(
            id: period.identity(id),
            missionId: id,
            period: period,
            source: .community(scope: scope),
            icon: icon,
            title: preferred.isEmpty ? fallback : preferred,
            rule: rule,
            goal: goal,
            reward: reward,
            params: nil,
            badgeId: badgeId
        )
    }

    private var icon: String {
        switch scope.uppercased() {
        case "WORLD": "globe"
        case "EUROPE": "globe.europe.africa.fill"
        default: "flag.fill"
        }
    }
}

/// Copia su disco delle missioni comuni per l'offline (cartella Caches, ricreabile).
enum CommunityMissionCache {
    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("community-missions.json")
    }

    static func load() -> [CommunityMission] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([CommunityMission].self, from: Data(contentsOf: url))
        } catch {
            communityLog.error("Cache missioni comuni illeggibile: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func save(_ missions: [CommunityMission]) {
        guard let url else { return }
        do {
            try JSONEncoder().encode(missions).write(to: url, options: .atomic)
        } catch {
            communityLog.error("Cache missioni comuni non salvata: \(error.localizedDescription, privacy: .public)")
        }
    }
}
