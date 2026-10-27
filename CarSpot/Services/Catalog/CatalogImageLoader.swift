import CryptoKit
import ImageIO
import SwiftUI
import UIKit
import os

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "catalog")

/// `NSCache` è thread-safe: questa scatola la rende condivisibile tra isolation.
private final class MemoryCache: @unchecked Sendable {
    let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
}

/// Immagini standard del catalogo: memoria + disco (`Caches/CatalogImages/`), download
/// con `URLSession`, miniatura decodificata con ImageIO fuori dal main thread.
actor CatalogImageLoader {
    static let shared = CatalogImageLoader()

    /// Cache in memoria condivisa e `nonisolated`: le celle già viste si leggono in modo
    /// sincrono, senza lampeggiare. Limite di costo in byte di pixel.
    private nonisolated static let memory = MemoryCache()

    private static func cacheKey(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.absoluteString)#\(maxPixel)" as NSString
    }

    /// Immagine già in memoria, se c'è (lettura sincrona, da qualunque isolation).
    nonisolated static func cachedImage(for url: URL, maxPixel: Int) -> UIImage? {
        memory.cache.object(forKey: cacheKey(url, maxPixel))
    }
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Download falliti di recente (bucket ancora vuoto, offline): non si riprova a ogni cella.
    private var failures: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 120

    private let directory = URL.cachesDirectory.appending(path: "CatalogImages", directoryHint: .isDirectory)

    func image(for url: URL, maxPixel: Int) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixel)"
        if let hit = Self.cachedImage(for: url, maxPixel: maxPixel) { return hit }
        if let task = inFlight[key] { return await task.value }
        if let failed = failures[url.absoluteString], Date.now.timeIntervalSince(failed) < Self.retryAfter {
            return nil
        }

        let task = Task { await self.load(url: url, maxPixel: maxPixel) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            Self.memory.cache.setObject(image, forKey: Self.cacheKey(url, maxPixel), cost: cost)
        } else {
            failures[url.absoluteString] = .now
        }
        return image
    }

    private func load(url: URL, maxPixel: Int) async -> UIImage? {
        let file = directory.appending(path: Self.fileName(for: url))
        var data = try? Data(contentsOf: file)
        if data == nil {
            guard let downloaded = await Self.download(url) else { return nil }
            data = downloaded
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? downloaded.write(to: file, options: .atomic)
        }
        guard let data, let cg = await decodeCatalogThumbnail(data, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cg.image)
    }

    private static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".webp"
    }

    @concurrent
    private static func download(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            log.debug("Immagine non scaricata: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Immagine già decodificata, passabile tra isolation.
private struct DecodedCatalogImage: @unchecked Sendable {
    let image: CGImage
}

/// Miniatura ImageIO (orientamento applicato, alpha conservato).
@concurrent
private func decodeCatalogThumbnail(_ data: Data, maxPixel: Int) async -> DecodedCatalogImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return DecodedCatalogImage(image: cg)
}

/// Immagine standard di una versione. Con `silhouette` diventa un'ombra in tinta unita
/// (l'alpha fa da maschera). Senza immagine, o mentre carica, mostra la sagoma della
/// carrozzeria: mai uno spinner.
struct CatalogImageView: View {
    let image: CatalogImage?
    let bodyType: BodyType
    var silhouette: Bool = false
    var maxPixel = 400
    /// Colore di ombra e sagoma di ripiego.
    var tint: Color = CSColor.nested

    @State private var loaded: UIImage?

    var body: some View {
        let url = image.flatMap { CatalogStore.shared.imageURL(for: $0) }
        // Se l'immagine è già in cache si vede al primo frame.
        let shown = loaded ?? url.flatMap { CatalogImageLoader.cachedImage(for: $0, maxPixel: maxPixel) }
        ZStack {
            if let loaded = shown {
                if silhouette {
                    Image(uiImage: loaded)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(uiImage: loaded)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(systemName: bodyType.symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(CSSpace.sm)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { loaded = nil; return }
            if let hit = CatalogImageLoader.cachedImage(for: url, maxPixel: maxPixel) { loaded = hit; return }
            loaded = nil
            loaded = await CatalogImageLoader.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}
