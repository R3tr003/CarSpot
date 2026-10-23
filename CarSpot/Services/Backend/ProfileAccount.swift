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
        case .usernameTaken: String(localized: "Nome già preso")
        case .invalidFormat: String(localized: "Formato non valido")
        case .unavailable: String(localized: "Servizio non disponibile al momento")
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
    /// Foto profilo: `avatarPath` null = nessuna; `avatarUpdatedAt` null = mai toccata
    /// (serve all'import automatico dall'account Google).
    private(set) var avatarPath: String?
    private(set) var avatarUpdatedAt: Date?
    private(set) var isAvatarBusy = false
    @ObservationIgnored private var avatarImportAttempted = false

    /// Versione corrente dell'avatar, `nil` se non c'è una foto.
    var avatar: AvatarRef? {
        guard let userId, let avatarPath, let avatarUpdatedAt else { return nil }
        return AvatarRef(userId: userId, path: avatarPath, version: avatarUpdatedAt)
    }

    // MARK: - Righe e payload

    private struct ProfileRow: Decodable, Sendable {
        let username: String?
        let onboardedAt: String?
        let avatarPath: String?
        let avatarUpdatedAt: String?
        enum CodingKeys: String, CodingKey {
            case username
            case onboardedAt = "onboarded_at"
            case avatarPath = "avatar_path"
            case avatarUpdatedAt = "avatar_updated_at"
        }
    }
    private struct AvatarRow: Decodable, Sendable {
        let avatarPath: String?
        let avatarUpdatedAt: String?
        enum CodingKeys: String, CodingKey {
            case avatarPath = "avatar_path"
            case avatarUpdatedAt = "avatar_updated_at"
        }
    }
    /// `avatar_path: null` va mandato esplicitamente per rimuovere la foto (`encodeIfPresent` lo ometterebbe).
    private struct AvatarUpdate: Encodable, Sendable {
        let path: String?
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case path = "avatar_path"
            case updatedAt = "avatar_updated_at"
        }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let path {
                try container.encode(path, forKey: .path)
            } else {
                try container.encodeNil(forKey: .path)
            }
            try container.encode(updatedAt, forKey: .updatedAt)
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
        avatarPath = nil
        avatarUpdatedAt = nil
        isAvatarBusy = false
        avatarImportAttempted = false
        if SupabaseBackend.shared == nil || Self.isCachedOnboarded(userId) {
            needsSetup = false
        } else {
            needsSetup = nil
        }
    }

    /// Legge `username` e `onboarded_at`. Da chiamare dopo `ensureProfile`.
    func load(userId: String) async {
        prepare(userId: userId)
        guard let backend = SupabaseBackend.shared else { return }
        // Utente già a posto (cache): niente setup da decidere, ma la foto va caricata comunque.
        guard needsSetup == nil else {
            await loadAvatar()
            return
        }

        // Rete lenta: dopo qualche secondo si entra comunque nell'app.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.loadTimeout)
            guard !Task.isCancelled, let self, self.userId == userId, self.needsSetup == nil else { return }
            Self.log.notice("Caricamento profilo lento: salto il setup per questo avvio")
            self.needsSetup = false
        }
        defer { watchdog.cancel() }

        do {
            let rows: [ProfileRow] = try await AppServices.errors.measure("profile.fetch", operation: "profile") {
                try await backend.client.from("profiles")
                    .select("username, onboarded_at, avatar_path, avatar_updated_at")
                    .eq("id", value: userId)
                    .limit(1)
                    .execute().value
            }
            guard self.userId == userId else { return }
            // La foto vale anche se nel frattempo il watchdog ha già lasciato entrare nell'app.
            if let row = rows.first, !isAvatarBusy {
                applyAvatar(path: row.avatarPath, updatedAt: row.avatarUpdatedAt)
                importAccountAvatarIfNeeded()
            }
            guard needsSetup == nil else { return }
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
            AppServices.errors.record(error, area: .profile, step: "load")
            if self.userId == userId, needsSetup == nil { needsSetup = false }
        }
    }

    /// Legge solo la foto del proprio profilo (utente già a posto: `load` non rifà la query completa).
    func loadAvatar() async {
        guard let backend = SupabaseBackend.shared, let userId else { return }
        do {
            let rows: [AvatarRow] = try await backend.client.from("profiles")
                .select("avatar_path, avatar_updated_at")
                .eq("id", value: userId)
                .limit(1)
                .execute().value
            guard self.userId == userId, !isAvatarBusy, let row = rows.first else { return }
            applyAvatar(path: row.avatarPath, updatedAt: row.avatarUpdatedAt)
            importAccountAvatarIfNeeded()
        } catch {
            Self.log.error("Caricamento avatar fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .profile, step: "avatar_load")
        }
    }

    private func applyAvatar(path: String?, updatedAt: String?) {
        avatarPath = path
        avatarUpdatedAt = updatedAt.flatMap(Self.parseDate)
    }

    // MARK: - Azioni

    /// `true` se nessun altro utente usa già `value`.
    func isUsernameAvailable(_ value: String) async throws -> Bool {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        do {
            let rows: [IdRow] = try await backend.client.from("profiles")
                .select("id")
                .eq("username", value: value)
                .neq("id", value: userId)
                .limit(1)
                .execute().value
            return rows.isEmpty
        } catch {
            AppServices.errors.record(error, area: .profile, step: "check_username")
            throw error
        }
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
            default:
                AppServices.errors.record(error, area: .profile, step: "save_username")
                throw error
            }
        } catch {
            AppServices.errors.record(error, area: .profile, step: "save_username")
            throw error
        }
    }

    /// Chiude il setup: `onboarded_at = now()`.
    func completeOnboarding() async throws {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        do {
            try await backend.client.from("profiles")
                .update(OnboardedUpdate(onboardedAt: ISO8601DateFormatter().string(from: .now)))
                .eq("id", value: userId)
                .execute()
        } catch {
            AppServices.errors.record(error, area: .profile, step: "complete_setup")
            throw error
        }
        Self.cacheOnboarded(userId)
        needsSetup = false
    }

    /// Rete assente durante il setup: entra nell'app per questo avvio (come il
    /// watchdog di `load`). `onboarded_at` resta null, quindi il setup ricompare al
    /// prossimo avvio online.
    func skipSetupForNow() {
        Self.log.notice("Setup rimandato dall'utente (offline)")
        needsSetup = false
    }

    // MARK: - Avatar

    /// Carica la foto (già compressa da `AvatarEncoding`) e la imposta come avatar.
    func setAvatar(jpeg: Data) async throws {
        isAvatarBusy = true
        defer { isAvatarBusy = false }
        try await uploadAvatar(jpeg)
        AppServices.analytics.track(.avatarUpdated(action: "set"))
    }

    /// Toglie la foto. La data resta valorizzata: l'import automatico non la rimette.
    func removeAvatar() async throws {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        isAvatarBusy = true
        defer { isAvatarBusy = false }
        do {
            do {
                _ = try await backend.client.storage.from(Self.avatarBucket).remove(paths: [Self.avatarObjectPath(userId)])
            } catch where Self.isNotFound(error) {
                // Già assente nel bucket: va bene così.
            }
            let version = Self.versionNow()
            try await backend.client.from("profiles")
                .update(AvatarUpdate(path: nil, updatedAt: Self.isoString(version)))
                .eq("id", value: userId)
                .execute()
            guard self.userId == userId else { return }
            avatarPath = nil
            avatarUpdatedAt = version
            AvatarCache.shared.removeAll(userId: userId)
            AppServices.analytics.track(.avatarUpdated(action: "removed"))
        } catch {
            AppServices.errors.record(error, area: .profile, step: "avatar_remove")
            throw error
        }
    }

    /// Prima volta con foto sull'account (Google): la importa da sola, una volta per avvio.
    /// Errori solo in log: non blocca mai.
    func importAccountAvatarIfNeeded() {
        guard avatarUpdatedAt == nil, avatarPath == nil, !isAvatarBusy, !avatarImportAttempted,
              SupabaseBackend.shared != nil, let userId,
              let url = AppServices.auth.accountImageURL else { return }
        avatarImportAttempted = true
        isAvatarBusy = true
        Task {
            defer { isAvatarBusy = false }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    Self.log.notice("Foto account non scaricabile: salto l'import")
                    return
                }
                guard let jpeg = await AvatarEncoding.encode(data: data, crop: nil) else {
                    Self.log.notice("Foto account non leggibile: salto l'import")
                    return
                }
                guard self.userId == userId else { return }
                try await uploadAvatar(jpeg)
            } catch {
                Self.log.error("Import avatar fallito: \(error.localizedDescription, privacy: .public)")
                AppServices.errors.record(error, area: .profile, step: "avatar_import")
            }
        }
    }

    /// Upload su `avatars/<userId>/avatar.jpg` (upsert) e poi riga `profiles`.
    private func uploadAvatar(_ jpeg: Data) async throws {
        guard let backend = SupabaseBackend.shared, let userId else { throw ProfileAccountError.unavailable }
        let path = Self.avatarObjectPath(userId)
        let version = Self.versionNow()
        do {
            try await backend.client.storage.from(Self.avatarBucket).upload(
                path, data: jpeg,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
            try await backend.client.from("profiles")
                .update(AvatarUpdate(path: path, updatedAt: Self.isoString(version)))
                .eq("id", value: userId)
                .execute()
        } catch {
            AppServices.errors.record(error, area: .profile, step: "avatar_upload")
            throw error
        }
        guard self.userId == userId else { return }
        avatarPath = path
        avatarUpdatedAt = version
        // I byte appena caricati vanno subito in cache: nessun download.
        AvatarCache.shared.store(jpeg, for: AvatarRef(userId: userId, path: path, version: version))
    }

    private static let avatarBucket = "avatars"

    private static func avatarObjectPath(_ userId: String) -> String { "\(userId)/avatar.jpg" }

    /// Adesso, a secondi interi: la chiave di cache usa i secondi e il server restituisce lo stesso valore.
    private static func versionNow() -> Date {
        Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Timestamp Postgres (`2026-10-21T10:00:00+00:00` o con frazioni): tollerante.
    nonisolated private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// Oggetto Storage inesistente (404 / "not found").
    private static func isNotFound(_ error: any Error) -> Bool {
        if let e = error as? StorageError {
            return e.statusCode == "404" || e.message.lowercased().contains("not found")
        }
        return false
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
