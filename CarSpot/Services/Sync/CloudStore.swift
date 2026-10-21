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
    /// Cursore del pull, impostato dal server: solo in lettura (escluso dall'encode).
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, make, model, year, rarity, power, agility, presence
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
    }
}

/// Valori di gioco assegnati dal server (xp/valuta/livello): il client li legge soltanto.
struct CloudProfile: Decodable, Sendable {
    let xp: Int
    let currency: Int
    let level: Int
}

/// Riscatto di un obiettivo del giorno. `day` = "yyyy-MM-dd".
struct CloudClaim: Codable, Sendable {
    let day: String
    let challengeId: String

    enum CodingKeys: String, CodingKey {
        case day
        case challengeId = "challenge_id"
    }
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
    /// Chiave primaria duplicata (23505) = già fatto = successo.
    func insertClaim(_ claim: CloudClaim) async throws
    func fetchClaims(sinceDay: String) async throws -> [CloudClaim]
}
