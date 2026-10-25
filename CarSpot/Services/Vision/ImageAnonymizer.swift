import UIKit
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import os

private let visionLog = Logger(subsystem: "com.carspot.andrea.app", category: "vision")


/// Riduce le foto con ImageIO (niente decodifica a piena risoluzione) e applica
/// l'orientamento EXIF ai pixel. Tutto fuori dal main actor.
enum ImageDownsampler {

    /// Dati grezzi (camera/libreria) → JPEG 0.85 con lato lungo ≤ 1600 px.
    @concurrent
    static func prepare(data: Data) async -> Data? {
        downsampledJPEG(from: data, maxPixel: 1600, quality: 0.85)
    }

    /// Miniatura (360 px) di un JPEG. Si ricava SOLO da quello già anonimizzato.
    @concurrent
    static func thumbnail(from data: Data) async -> Data? {
        downsampledJPEG(from: data, maxPixel: 360, quality: 0.6)
    }

    static func downsampledJPEG(from data: Data, maxPixel: Int, quality: CGFloat) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        // Mai ingrandire: il limite non supera il lato lungo originale.
        var limit = maxPixel
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            limit = min(maxPixel, max(w, h))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            visionLog.error("Riduzione immagine fallita")
            return nil
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// Perché l'anonimizzazione non è riuscita. Nessun dato dell'utente nel caso.
enum AnonymizationError: Error, Equatable, Sendable {
    /// Il JPEG non si decodifica in un'immagine analizzabile.
    case undecodable
    /// Vision non ha potuto analizzare l'immagine: non sappiamo se ci sono volti/targhe.
    case analysisFailed
    /// Regioni sensibili trovate ma sfocatura o codifica fallite.
    case blurFailed
}

/// On-device privacy pass. Detects faces and license-plate-like text regions and
/// blurs them BEFORE the image is ever shown, saved or sent. Runs off the main
/// actor; takes and returns JPEG `Data` so nothing non-Sendable crosses actors.
/// Riceve immagini già ridotte (≤1600 px): Vision e CoreImage restano veloci.
///
/// **Fail-closed:** "nessuna regione sensibile" è l'unico caso in cui l'originale passa
/// com'è. Se non si riesce ad analizzare o sfocare, `anonymize` lancia: mai l'originale.
enum ImageAnonymizer {

    /// Rilevatore di regioni sensibili (normalizzate, origine in basso a sinistra).
    /// Iniettabile per i test; lancia se l'analisi non è possibile.
    typealias RegionDetector = @Sendable (CGImage) throws -> [CGRect]

    /// CIContext è thread-safe ma non `Sendable`: condiviso per non ricrearlo a ogni scatto.
    private static let ciContext = CIContext()

    /// Returns an anonymized JPEG, o l'input se non c'è nulla da oscurare.
    /// Throws `AnonymizationError` se non può garantire l'anonimato.
    @concurrent
    static func anonymize(jpegData: Data) async throws -> Data {
        try anonymize(jpegData: jpegData, detector: visionRegions)
    }

    /// Parte sincrona e pura rispetto a Vision: testabile con un rilevatore finto.
    static func anonymize(jpegData: Data, detector: RegionDetector) throws -> Data {
        guard let image = UIImage(data: jpegData),
              let cg = image.cgImage else {
            visionLog.error("Anonimizzazione: immagine non decodificabile")
            throw AnonymizationError.undecodable
        }

        let regions: [CGRect]
        do {
            regions = try detector(cg)
        } catch {
            visionLog.error("Vision fallita: \(error.localizedDescription)")
            throw AnonymizationError.analysisFailed
        }
        guard !regions.isEmpty else { return jpegData }

        guard let blurred = blur(image: image, cg: cg, normalizedRegions: regions),
              let out = blurred.jpegData(compressionQuality: 0.85) else {
            visionLog.error("Anonimizzazione: sfocatura o codifica fallite")
            throw AnonymizationError.blurFailed
        }
        return out
    }

    // MARK: Detection (Vision boundingBoxes are normalized, origin bottom-left)

    private static let visionRegions: RegionDetector = { cg in
        var rects: [CGRect] = []

        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        try handler.perform([faceRequest, textRequest])

        if let faces = faceRequest.results {
            rects += faces.map { $0.boundingBox.insetBy(dx: -0.02, dy: -0.02) }
        }
        if let texts = textRequest.results {
            for obs in texts {
                guard let candidate = obs.topCandidates(1).first else { continue }
                if looksLikePlate(candidate.string) {
                    rects.append(obs.boundingBox.insetBy(dx: -0.01, dy: -0.01))
                }
            }
        }
        return rects
    }

    /// Heuristic for European-style plates: 5–8 chars, mostly uppercase + digits.
    static func looksLikePlate(_ s: String) -> Bool {
        let trimmed = s.replacingOccurrences(of: " ", with: "")
        guard (5...8).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits)
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let onlyAllowed = trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        return hasDigit && onlyAllowed
    }

    // MARK: Compositing

    private static func blur(image: UIImage, cg: CGImage, normalizedRegions: [CGRect]) -> UIImage? {
        let ciImage = CIImage(cgImage: cg)

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(cg.width, cg.height) / 28, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let blurredCG = Self.ciContext.createCGImage(output, from: ciImage.extent) else { return nil }
        let blurredImage = UIImage(cgImage: blurredCG)

        let size = image.size
        // Scala 1: i pixel restano quelli dell'immagine ridotta (non ×3 dello schermo).
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(at: .zero)
            for n in normalizedRegions {
                // Vision normalized (bottom-left) → UIKit points (top-left).
                let rect = CGRect(
                    x: n.minX * size.width,
                    y: (1 - n.maxY) * size.height,
                    width: n.width * size.width,
                    height: n.height * size.height
                )
                // Draw the corresponding slice of the fully-blurred image.
                if let slice = blurredImage.cgImage?.cropping(to: CGRect(
                    x: n.minX * size.width * image.scale,
                    y: (1 - n.maxY) * size.height * image.scale,
                    width: n.width * size.width * image.scale,
                    height: n.height * size.height * image.scale
                )) {
                    UIImage(cgImage: slice).draw(in: rect)
                }
            }
        }
    }
}
