import Foundation

/// Carta come la vede il cloud (`public.cards`). Colonne in snake_case.
struct CloudCard: Codable, Sendable {
    let id: UUID
    let ownerId: String
    let make: String
    let model: String
    let year: Int?
    let rarity: String
    let colorName: String?
    let power: Int
    let agility: Int
    let presence: Int
    let photoPath: String?
    let spottedArea: String?
    let capturedAt: Date
    /// Stessa auto già catturata: 0 premi. Il server può metterla a true da solo (stesso
    /// posto nelle 24 ore); `nil` dalle righe vecchie = false.
    let isRepeat: Bool?
    /// Cursore del pull, impostato dal server: solo in lettura (escluso dall'encode).
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, make, model, year, rarity, power, agility, presence
        case isRepeat = "is_repeat"
        case ownerId = "owner_id"
        case colorName = "color_name"
        case photoPath = "photo_path"
        case spottedArea = "spotted_area"
        case capturedAt = "captured_at"
        case createdAt = "created_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encode(make, forKey: .make)
        try c.encode(model, forKey: .model)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encode(rarity, forKey: .rarity)
        try c.encodeIfPresent(colorName, forKey: .colorName)
        try c.encode(power, forKey: .power)
        try c.encode(agility, forKey: .agility)
        try c.encode(presence, forKey: .presence)
        try c.encodeIfPresent(photoPath, forKey: .photoPath)
        try c.encodeIfPresent(spottedArea, forKey: .spottedArea)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(isRepeat ?? false, forKey: .isRepeat)
    }
}

/// Valori di gioco assegnati dal server (xp/valuta/livello): il client li legge soltanto.
struct CloudProfile: Decodable, Sendable {
    let xp: Int
    let currency: Int
    let level: Int
}

/// Riscatto di una missione (`public.mission_claims`). Il premio lo decide il server.
struct CloudMissionClaim: Codable, Sendable {
    /// "day" | "week" | "month" | "community".
    let period: String
    /// "yyyy-MM-dd".
    let periodStart: String
    let missionId: String
    let goal: Int
    let params: MissionParams?
    /// Inizio del periodo all'ora del telefono; opzionale in lettura (colonna nullable).
    let windowStart: Date?
    /// Fine (esclusa) del periodo; il server la valida contro il periodo locale reale.
    let windowEnd: Date?

    enum CodingKeys: String, CodingKey {
        case period, goal, params
        case periodStart = "period_start"
        case missionId = "mission_id"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }

    init(_ payload: MissionClaimPayload) {
        period = payload.period.rawValue
        periodStart = payload.periodStart
        missionId = payload.missionId
        goal = payload.goal
        params = payload.params
        windowStart = payload.windowStart
        windowEnd = payload.windowEnd
    }

    /// Identità locale del riscatto, uguale a `Mission.id`.
    var identity: String { "\(period):\(periodStart)|\(missionId)" }
}

/// Persistenza cloud dietro protocollo (convenzione del progetto). Un solo tentativo per
/// chiamata: i retry li gestisce `SyncService` al prossimo `syncNow`.
protocol CloudStore: Sendable {
    /// Insert idempotente sull'`id` (`on conflict do nothing`): un retry non duplica
    /// e il trigger dei premi non scatta due volte.
    func insertCard(_ card: CloudCard) async throws
    /// Upload JPEG; "già esistente" (409) conta come successo.
    func uploadPhoto(_ data: Data, path: String) async throws
    func downloadPhoto(path: String) async throws -> Data
    /// Righe con `created_at >= createdAfter`, ordinate per `created_at` crescente.
    func fetchCards(createdAfter: Date?, offset: Int, limit: Int) async throws -> [CloudCard]
    func fetchProfile(userId: String) async throws -> CloudProfile?
    /// Chiave primaria duplicata (23505) = già fatto = successo. Errori di regola = P0001.
    func insertMissionClaim(_ claim: CloudMissionClaim) async throws
    /// Riscatti con `period_start >= sinceDay` ("yyyy-MM-dd").
    func fetchMissionClaims(sinceDay: String) async throws -> [CloudMissionClaim]
    /// Id dei badge ottenuti (`player_badges.badge_id`).
    func fetchBadges() async throws -> [String]
    /// Missioni comuni con `ends_on >= day` ("yyyy-MM-dd").
    func fetchCommunityMissions(endingAfter day: String) async throws -> [CommunityMission]
}
