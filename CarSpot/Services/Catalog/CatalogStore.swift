import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "catalog")

/// Catalogo già pronto per l'uso: dati, indice e abbinamento.
private struct LoadedCatalog: Sendable {
    let snapshot: CatalogSnapshot
    let index: CatalogIndex
    let matcher: CatalogMatcher

    init(_ snapshot: CatalogSnapshot) {
        let index = CatalogIndex(snapshot)
        self.snapshot = snapshot
        self.index = index
        self.matcher = CatalogMatcher(index: index)
    }
}

/// Catalogo condiviso letto dall'album. Parte dallo snapshot nel bundle (o dalla cache su
/// disco, se più recente) e poi chiede a Supabase solo le righe cambiate.
/// Il collegamento in `AppServices` è un seguito: per ora si crea da solo.
@MainActor
@Observable
final class CatalogStore {
    static let shared = CatalogStore()

    /// `nil` finché lo snapshot non è pronto (al massimo un frame: sta nel bundle).
    private(set) var index: CatalogIndex?
    private(set) var matcher: CatalogMatcher?
    private(set) var imageBaseURL: URL?

    @ObservationIgnored private var didLoad = false

    init() {}

    /// URL pubblico dell'immagine standard; `nil` se il catalogo non è ancora caricato.
    func imageURL(for image: CatalogImage) -> URL? {
        imageBaseURL?.appending(path: image.path)
    }

    /// Una volta sola: snapshot locale, poi aggiornamento remoto in silenzio.
    func load() async {
        guard !didLoad else { return }
        didLoad = true

        guard let local = await loadLocalCatalog() else {
            // Mai uno spinner infinito: catalogo vuoto, l'album mostra gli stati vuoti.
            log.fault("Nessuno snapshot del catalogo disponibile")
            publish(LoadedCatalog(Self.emptySnapshot))
            return
        }
        publish(local)
        log.info("Catalogo locale: \(local.index.modelCount) modelli")

        guard let client = SupabaseBackend.shared?.client else { return }
        do {
            let changes = try await SupabaseCatalogService(client: client)
                .changes(since: local.snapshot.newestUpdate)
            guard !changes.isEmpty else { return }
            let merged = await mergeCatalog(local.snapshot, changes)
            publish(merged)
            log.info("Catalogo aggiornato: \(merged.index.modelCount) modelli")
        } catch {
            // Offline o ospite: si resta con quello che c'è, senza messaggi.
            log.error("Aggiornamento catalogo fallito: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publish(_ loaded: LoadedCatalog) {
        index = loaded.index
        matcher = loaded.matcher
        imageBaseURL = loaded.snapshot.imageBaseURL
    }

    private static let emptySnapshot = CatalogSnapshot(
        version: 1, generatedAt: .distantPast,
        imageBaseURL: URL(string: "https://invalid.example/")!,
        makes: [], models: [], variants: []
    )
}

// MARK: - Fuori dal main actor

private var cacheURL: URL {
    URL.applicationSupportDirectory.appending(path: "Catalog/catalog.json")
}

/// Bundle o cache su disco: vince quello con `newestUpdate` più recente.
@concurrent
private func loadLocalCatalog() async -> LoadedCatalog? {
    let bundled = try? CatalogSnapshot.bundled()
    let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? CatalogSnapshot.decode($0) }
    switch (bundled, cached) {
    case let (b?, c?): return LoadedCatalog(c.newestUpdate > b.newestUpdate ? c : b)
    case let (b?, nil): return LoadedCatalog(b)
    case let (nil, c?): return LoadedCatalog(c)
    case (nil, nil): return nil
    }
}

/// Unisce le novità, salva la cache e ricostruisce l'indice.
@concurrent
private func mergeCatalog(_ base: CatalogSnapshot, _ changes: CatalogChanges) async -> LoadedCatalog {
    let merged = base.merging(changes)
    do {
        let url = cacheURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try merged.encoded().write(to: url, options: .atomic)
    } catch {
        log.error("Cache del catalogo non salvata: \(error.localizedDescription, privacy: .public)")
    }
    return LoadedCatalog(merged)
}
