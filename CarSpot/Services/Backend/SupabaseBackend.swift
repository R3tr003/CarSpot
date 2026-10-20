import Foundation
import Supabase
import os

/// Client Supabase condiviso. Esiste solo con Supabase E Clerk configurati: senza,
/// `shared` è `nil` e l'app resta locale. L'utente è identificato dal JWT di sessione
/// Clerk (third-party auth) → RLS legge `auth.jwt()->>'sub'`.
/// Non toccare `client.auth`: con `accessToken` custom non è consentito.
@MainActor
final class SupabaseBackend {
    static let shared: SupabaseBackend? =
        (AppConfig.isSupabaseConfigured && AppConfig.isClerkConfigured) ? SupabaseBackend() : nil

    private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "backend")

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: .init(auth: .init(accessToken: {
                // Il token Clerk dura ~1 minuto: lo si chiede a ogni richiesta.
                try await SupabaseBackend.currentToken()
            }))
        )
    }

    /// Passa dal main actor: l'esistenziale `any AuthService` non è `Sendable`, quindi
    /// la closure `@Sendable` del client riceve solo la stringa del token.
    private static func currentToken() async throws -> String? {
        try await AppServices.auth.sessionToken()
    }

    // MARK: - Profilo

    private struct ProfileIdRow: Decodable, Sendable { let id: String }
    private struct NewProfile: Encodable, Sendable {
        let id: String
        let username: String
    }

    /// Crea la riga `profiles` al primo accesso (solo `id` e `username` sono inseribili;
    /// xp/level/currency li scrive il backend). Idempotente.
    func ensureProfile(userId: String) async throws {
        let profiles = client.from("profiles")

        let existing: [ProfileIdRow] = try await profiles
            .select("id").eq("id", value: userId).limit(1).execute().value
        guard existing.isEmpty else { return }

        // Username dagli ultimi caratteri dell'id; se collide (unique) si allunga il suffisso.
        let tail = userId.lowercased()
        for length in [6, 12] {
            let row = NewProfile(id: userId, username: "spotter_" + String(tail.suffix(length)))
            do {
                try await profiles.insert(row).execute()
                return
            } catch let error as PostgrestError where error.code == "23505" {
                // Violazione di unicità: o corsa sull'id (già creato) o username occupato.
                let now: [ProfileIdRow] = try await profiles
                    .select("id").eq("id", value: userId).limit(1).execute().value
                if !now.isEmpty { return }
                Self.log.notice("Username occupato, riprovo con suffisso più lungo")
            }
        }
    }
}
