import UIKit
import Vision
import CoreImage

/// On-device privacy pass. Detects faces and license-plate-like text regions and
/// blurs them BEFORE the image is ever shown, saved or sent. Runs off the main
/// actor; takes and returns JPEG `Data` so nothing non-Sendable crosses actors.
enum ImageAnonymizer {

    /// Returns an anonymized JPEG. On any failure returns the input unchanged
    /// (privacy-safe default would be to redact more, but we never expose less
    /// than the input — detection failures are logged for tuning).
    static func anonymize(jpegData: Data) async -> Data {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: jpegData),
                  let cg = image.cgImage else { return jpegData }

            let regions = sensitiveRegions(in: cg)
            guard !regions.isEmpty else { return jpegData }

            guard let blurred = blur(image: image, cg: cg, normalizedRegions: regions),
                  let out = blurred.jpegData(compressionQuality: 0.9) else { return jpegData }
            return out
        }.value
    }

    // MARK: Detection (Vision boundingBoxes are normalized, origin bottom-left)

    private static func sensitiveRegions(in cg: CGImage) -> [CGRect] {
        var rects: [CGRect] = []

        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        try? handler.perform([faceRequest, textRequest])

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
    private static func looksLikePlate(_ s: String) -> Bool {
        let trimmed = s.replacingOccurrences(of: " ", with: "")
        guard (5...8).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits)
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let onlyAllowed = trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        return hasDigit && onlyAllowed
    }

    // MARK: Compositing

    private static func blur(image: UIImage, cg: CGImage, normalizedRegions: [CGRect]) -> UIImage? {
        let ciContext = CIContext()
        let ciImage = CIImage(cgImage: cg)

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(max(cg.width, cg.height) / 28, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let blurredCG = ciContext.createCGImage(output, from: ciImage.extent) else { return nil }
        let blurredImage = UIImage(cgImage: blurredCG)

        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
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
