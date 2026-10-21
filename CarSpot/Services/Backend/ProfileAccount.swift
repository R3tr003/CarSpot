import Foundation
import Supabase
import os

/// Errori tipizzati del profilo, con messaggio già pronto per l'utente.
enum ProfileAccountError: LocalizedError, Sendable {
    case usernameTaken
    case invalidFormat
    case unavailable

    var errorDescription: String? {
        switch self {
        case .usernameTaken: "Nome già preso"
        case .invalidFormat: "Formato non valido"
        case .unavailable: "Servizio non disponibile al momento"
        }
    }
}

/// Stato "account" della riga `profiles` dell'utente Clerk: nome da spotter e
/// completamento del primo setup (`onboarded_at`). Non blocca mai l'utente:
/// senza backend o con errori di rete `needsSetup` diventa `false`.
@MainActor
@Observable
final class ProfileAccount {
    private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "profile")
    private static let cacheKey = "profileOnboardedUserIds"
    private static let loadTimeout: Duration = .seconds(10)

    /// Utente a cui si riferisce lo stato qui sotto.
    private(set) var userId: String?
    private(set) var username = ""
    /// `nil` = non ancora noto (caricamento); `true` = mostrare il setup.
    private(set) var needsSetup: Bool?

    // MARK: - Righe e payload

    private struct ProfileRow: Decodable, Sendable {
        let username: String?
        let onboardedAt: String?
        enum CodingKeys: String, CodingKey {
            case username
            case onboardedAt = "onboarded_at"
        }
    }
    private struct IdRow: Decodable, Sendable { let id: String }
    private struct UsernameUpdate: Encodable, Sendable { let username: String }
    private struct OnboardedUpdate: Encodable, Sendable {
        let onboardedAt: String
        enum CodingKeys: String, CodingKey { case onboardedAt = "onboarded_at" }
    }

    // MARK: - Validazione

    nonisolated private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")

    /// Minuscolo, solo caratteri ammessi, massimo 20: per filtrare mentre si digita.
    nonisolated static func sanitize(_ text: String) -> String {
        String(text.lowercased().filter { allowed.contains($0) }.prefix(20))
    }

    /// Stessa regola del check DB: `^[a-z0-9_.]{3,20}$`.
    nonisolated static func isValid(_ text: String) -> Bool {
        (3...20).contains(text.count) && text.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Caricamento

    /// Sincrono: imposta l'utente e, se sappiamo già che ha finito il setup, evita il
    /// caricamento di rete (nessun flash a ogni avvio).
    func prepare(userId: String) {
        guard self.userId != userId else { return }
        self.userId = userId
        username = ""
        if SupabaseBackend.shared == nil || Self.isCachedOnboarded(userId) {
            needsSetup = false
        } else {
            needsSetup = nil
        }
    }

    /// Legge `username` e `onboarded_at`. Da chiamare dopo `ensureProfile`.
    func load(userId: String) async {
        prepare(userId: userId)
        guard needsSetup == nil, let backend = SupabaseBackend.shared else { return }

        // Rete lenta: dopo qualche secondo si entra comunque nell'app.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.loadTimeout)
            guard !Task.isCancelled, let self, self.userId == userId, self.needsSetup == nil else { return }
            Self.log.notice("Caricamento profilo lento: salto il setup per questo avvio")
            self.needsSetup = false
        }
        defer { watchdog.cancel() }

        do {
            let rows: [ProfileRow] = try await backend.client.from("profiles")
                .select("username, onboarded_at")
                .eq("id", value: userId)
                .limit(1)
                .execute().value
            guard self.userId == userId, needsSetup == nil else { return }
            guard let row = rows.first else {
                // Riga non ancora creata: non bloccare.
                needsSetup = false
                return
            }
            username = row.username ?? ""
            if row.onboardedAt != nil {
                Self.cacheOnboarded(userId)
                needsSetup = false
            } else {
                needsSetup = true
            }
        } catch {
            Self.log.error("Caricamento profilo fallito: \(error.localizedDescription, privacy: .public)")
            if self.userId == userId, needsSetup == nil { needsSetup = false }
        }
    }

    // MARK: - Azioni

    /// `true` se nessun altro utente usa già `value`.
    func isUsernameAvailable(_ value: String) async throws -> Bool {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        let rows: [IdRow] = try await backend.client.from("profiles")
            .select("id")
            .eq("username", value: value)
            .neq("id", value: userId)
            .limit(1)
            .execute().value
        return rows.isEmpty
    }

    func saveUsername(_ value: String) async throws {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        guard Self.isValid(value) else { throw ProfileAccountError.invalidFormat }
        do {
            try await backend.client.from("profiles")
                .update(UsernameUpdate(username: value))
                .eq("id", value: userId)
                .execute()
            username = value
        } catch let error as PostgrestError {
            switch error.code {
            case "23505": throw ProfileAccountError.usernameTaken
            case "23514": throw ProfileAccountError.invalidFormat
            default: throw error
            }
        }
    }

    /// Chiude il setup: `onboarded_at = now()`.
    func completeOnboarding() async throws {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        try await backend.client.from("profiles")
            .update(OnboardedUpdate(onboardedAt: ISO8601DateFormatter().string(from: .now)))
            .eq("id", value: userId)
            .execute()
        Self.cacheOnboarded(userId)
        needsSetup = false
    }

    // MARK: - Cache locale degli utenti già a posto (solo id, nessun dato personale)

    private static func isCachedOnboarded(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: cacheKey) ?? []).contains(id)
    }

    private static func cacheOnboarded(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: cacheKey) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: cacheKey)
    }
}
