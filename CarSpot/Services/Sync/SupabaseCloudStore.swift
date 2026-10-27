import Foundation
import Supabase

/// `CloudStore` sopra il client Supabase condiviso (token Clerk via `accessToken`).
/// Mai `client.auth`: con `accessToken` custom non è consentito.
final class SupabaseCloudStore: CloudStore {
    private static let bucket = "spots"

    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insertCard(_ card: CloudCard) async throws {
        try await client.from("cards")
            .upsert(card, onConflict: "id", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }

    func uploadPhoto(_ data: Data, path: String) async throws {
        do {
            try await client.storage.from(Self.bucket).upload(
                path, data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        } catch where Self.isAlreadyExists(error) {
            // Upload già riuscito in un tentativo precedente: va bene così.
        }
    }

    func downloadPhoto(path: String) async throws -> Data {
        try await client.storage.from(Self.bucket).download(path: path)
    }

    func fetchCards(createdAfter: Date?, offset: Int, limit: Int) async throws -> [CloudCard] {
        var query = client.from("cards").select()
        if let createdAfter {
            query = query.gte("created_at", value: Self.isoString(createdAfter))
        }
        return try await query
            .order("created_at", ascending: true)
            .order("id", ascending: true)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
    }

    func fetchProfile(userId: String) async throws -> CloudProfile? {
        let rows: [CloudProfile] = try await client.from("profiles")
            .select("xp,currency,level")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func insertMissionClaim(_ claim: CloudMissionClaim) async throws {
        do {
            try await client.from("mission_claims")
                .insert(claim, returning: .minimal)
                .execute()
        } catch let error as PostgrestError where error.code == "23505" {
            // Riscatto già registrato (chiave primaria duplicata).
        }
    }

    func fetchMissionClaims(sinceDay: String) async throws -> [CloudMissionClaim] {
        try await client.from("mission_claims")
            .select("period,period_start,mission_id,goal,params,window_start")
            .gte("period_start", value: sinceDay)
            .execute()
            .value
    }

    func fetchBadges() async throws -> [String] {
        struct Row: Decodable { let badgeId: String
            enum CodingKeys: String, CodingKey { case badgeId = "badge_id" } }
        let rows: [Row] = try await client.from("player_badges")
            .select("badge_id")
            .execute()
            .value
        return rows.map(\.badgeId)
    }

    func fetchCommunityMissions(endingAfter day: String) async throws -> [CommunityMission] {
        try await client.from("community_missions")
            .select("id,scope,title_it,title_en,starts_on,ends_on,rule,goal,reward,badge_id")
            .gte("ends_on", value: day)
            .order("starts_on", ascending: true)
            .execute()
            .value
    }

    // MARK: - Privato

    /// Storage risponde 400 con corpo `{"statusCode":"409","error":"Duplicate",...}` (o 409
    /// diretto): si riconosce da codice, tipo di errore o messaggio.
    private static func isAlreadyExists(_ error: any Error) -> Bool {
        if let e = error as? StorageError {
            return e.statusCode == "409"
                || e.error?.lowercased() == "duplicate"
                || e.message.lowercased().contains("already exists")
        }
        if let e = error as? HTTPError {
            return e.response.statusCode == 409
        }
        return false
    }

    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
