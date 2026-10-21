import Foundation

/// A candidate match returned by the recognition pipeline. The year is an
/// estimate by design (real-world accuracy ~75–85% ±2y), hence optional/soft.
struct VehicleCandidate: Identifiable, Hashable, Sendable, Codable {
    var id = UUID()
    var make: String
    var model: String
    var yearEstimate: Int?
    /// 0...1 model confidence.
    var confidence: Double

    var title: String { "\(make) \(model)" }
    var confidencePercent: Int { Int((confidence * 100).rounded()) }

    private enum CodingKeys: String, CodingKey { case make, model, yearEstimate, confidence }
}

enum RecognitionError: LocalizedError {
    case noMatch
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noMatch: return String(localized: "Nessuna auto riconosciuta. Prova un'inquadratura frontale 3/4.")
        case .network(let m): return String(localized: "Errore di rete: \(m)")
        }
    }
}

/// Turns an (already anonymized) JPEG into ranked candidate matches.
/// `Data` rather than `UIImage` so it crosses actor boundaries safely.
protocol RecognitionService: Sendable {
    func recognize(imageData: Data) async throws -> [VehicleCandidate]
}
