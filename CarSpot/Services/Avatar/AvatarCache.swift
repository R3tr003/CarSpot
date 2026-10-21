import UIKit
import Supabase
import os

/// Riferimento a una versione precisa dell'avatar di un utente: la data cambia a ogni
/// nuova foto, quindi la chiave di cache si invalida da sola.
struct AvatarRef: Hashable, Sendable {
    let userId: String
    /// Percorso nel bucket `avatars` (`<userId>/avatar.jpg`).
    let path: String
    let version: Date

    var cacheKey: String { "\(userId)-\(Int(version.timeIntervalSince1970))" }
}

/// Cache degli avatar: memoria + disco (`Caches/avatars/<userId>-<versione>.jpg`), poi
/// download dal bucket privato `avatars` col client Supabase autenticato.
/// Ogni avatar si scarica una sola volta per versione.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    nonisolated private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "avatar")
    private static let bucket = "avatars"

    private let memory = NSCache<NSString, UIImage>()
    /// Chiavi in memoria per utente (NSCache non si può enumerare).
    private var memoryKeys: [String: Set<String>] = [:]
    /// Download in corso per chiave: chiamate concorrenti condividono lo stesso lavoro.
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 64
    }

    nonisolated private static var directory: URL {
        URL.cachesDirectory.appending(path: "avatars", directoryHint: .isDirectory)
    }

    // MARK: - API

    func image(for ref: AvatarRef) async -> UIImage? {
        let key = ref.cacheKey
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = inflight[key] { return await running.value }

        let task = Task { await load(ref) }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    /// Mette subito in cache i byte appena caricati (nessun download dopo l'upload).
    func store(_ data: Data, for ref: AvatarRef) {
        if let image = UIImage(data: data) { remember(image, for: ref) }
        Task { await Self.writeToDisk(data, key: ref.cacheKey, userId: ref.userId) }
    }

    /// Foto rimossa: via da memoria e disco, qualunque versione.
    func removeAll(userId: String) {
        for key in memoryKeys[userId] ?? [] { memory.removeObject(forKey: key as NSString) }
        memoryKeys[userId] = nil
        Task { await Self.deleteFromDisk(userId: userId, keeping: nil) }
    }

    // MARK: - Privato

    private func load(_ ref: AvatarRef) async -> UIImage? {
        if let cached = await Self.readFromDisk(key: ref.cacheKey) {
            remember(cached, for: ref)
            return cached
        }
        guard let backend = SupabaseBackend.shared else { return nil }
        do {
            let data = try await backend.client.storage.from(Self.bucket).download(path: ref.path)
            guard let image = UIImage(data: data) else {
                Self.log.error("Avatar scaricato non leggibile")
                return nil
            }
            remember(image, for: ref)
            await Self.writeToDisk(data, key: ref.cacheKey, userId: ref.userId)
            return image
        } catch {
            Self.log.error("Download avatar fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .profile, step: "avatar_download")
            return nil
        }
    }

    private func remember(_ image: UIImage, for ref: AvatarRef) {
        memory.setObject(image, forKey: ref.cacheKey as NSString)
        memoryKeys[ref.userId, default: []].insert(ref.cacheKey)
    }

    // MARK: - Disco (fuori dal main)

    @concurrent
    private static func readFromDisk(key: String) async -> UIImage? {
        let url = directory.appending(path: "\(key).jpg")
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return image
    }

    /// Scrive la versione nuova e cancella le vecchie dello stesso utente.
    @concurrent
    private static func writeToDisk(_ data: Data, key: String, userId: String) async {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: "\(key).jpg"), options: .atomic)
        } catch {
            log.error("Scrittura avatar su disco fallita: \(error.localizedDescription, privacy: .public)")
            return
        }
        deleteVersions(userId: userId, keeping: key)
    }

    @concurrent
    private static func deleteFromDisk(userId: String, keeping key: String?) async {
        deleteVersions(userId: userId, keeping: key)
    }

    nonisolated private static func deleteVersions(userId: String, keeping key: String?) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let keptName = key.map { "\($0).jpg" }
        for name in files where name.hasPrefix("\(userId)-") && name != keptName {
            try? fm.removeItem(at: directory.appending(path: name))
        }
    }
}
