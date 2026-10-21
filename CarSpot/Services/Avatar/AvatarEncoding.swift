import UIKit
import ImageIO
import UniformTypeIdentifiers
import os

private let avatarLog = Logger(subsystem: "com.carspot.andrea.app", category: "avatar")

/// Foto grezza → JPEG quadrato 512×512 sotto i 100 KB, pronto per Storage.
/// Tutto fuori dal main actor (ImageIO + CoreGraphics), come `ImageDownsampler`.
enum AvatarEncoding {
    /// Lato dell'avatar salvato, in pixel.
    static let side = 512
    /// Peso massimo desiderato (il bucket accetta fino a 200 KB).
    static let maxBytes = 100_000
    private static let qualities: [CGFloat] = [0.8, 0.7, 0.6, 0.5]

    /// `crop`: rettangolo NORMALIZZATO (0…1, origine in alto a sinistra) rispetto all'immagine
    /// già orientata; `nil` = quadrato centrale. `nil` in uscita se i dati non sono leggibili.
    @concurrent
    static func encode(data: Data, crop: CGRect?) async -> Data? {
        guard let image = orientedImage(from: data, maxPixel: 2048) else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Rettangolo di ritaglio in pixel, reso quadrato e contenuto nell'immagine.
        var rect: CGRect
        if let crop {
            rect = CGRect(x: crop.minX * width, y: crop.minY * height,
                          width: crop.width * width, height: crop.height * height)
        } else {
            rect = CGRect(x: 0, y: 0, width: width, height: height)
        }
        let edge = max(1, min(rect.width, rect.height, width, height))
        rect = CGRect(x: rect.midX - edge / 2, y: rect.midY - edge / 2, width: edge, height: edge)
        rect.origin.x = min(max(0, rect.origin.x), width - edge)
        rect.origin.y = min(max(0, rect.origin.y), height - edge)

        guard let cropped = image.cropping(to: rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))) else {
            return nil
        }
        // Mai ingrandire: se il ritaglio è più piccolo di 512 resta del suo lato.
        let target = min(side, cropped.width, cropped.height)
        guard let scaled = resized(cropped, to: target) else { return nil }

        var last: Data?
        for quality in qualities {
            guard let jpeg = jpegData(scaled, quality: quality) else { continue }
            last = jpeg
            if jpeg.count < maxBytes { break }
        }
        if last == nil { avatarLog.error("Codifica avatar fallita") }
        return last
    }

    /// Immagine orientata per mostrarla nel ritaglio (max `maxPixel` sul lato lungo),
    /// senza decodificare la foto a piena risoluzione sul main.
    @concurrent
    static func displayImage(data: Data, maxPixel: Int = 2048) async -> CGImage? {
        orientedImage(from: data, maxPixel: maxPixel)
    }

    // MARK: - Privato

    /// Thumbnail ImageIO con l'orientamento EXIF applicato ai pixel.
    private static func orientedImage(from data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Ridisegna in un quadrato `side`×`side` su fondo bianco (il JPEG non ha trasparenza).
    private static func resized(_ image: CGImage, to side: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(full)
        context.interpolationQuality = .high
        context.draw(image, in: full)
        return context.makeImage()
    }

    private static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
