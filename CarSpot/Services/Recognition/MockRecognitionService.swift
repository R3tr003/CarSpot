import Foundation

/// Offline stand-in for the real recognition API. Returns a small ranked set of
/// plausible candidates so the whole capture → confirm → save flow is testable
/// on the simulator without keys. Picks a pseudo-random vehicle per call.
struct MockRecognitionService: RecognitionService {

    private static let catalog: [(String, String, Int)] = [
        ("Alfa Romeo", "Giulia Quadrifoglio", 2022),
        ("Lancia", "Delta Integrale", 1992),
        ("Volkswagen", "Golf GTI", 2019),
        ("Fiat", "Panda", 2015),
        ("Porsche", "911 Carrera", 2021),
        ("Mini", "Cooper S", 2018),
        ("BMW", "M3 Competition", 2023),
        ("Renault", "Clio", 2016),
        ("Abarth", "595 Competizione", 2020),
        ("Toyota", "Yaris", 2017)
    ]

    func recognize(imageData: Data) async throws -> [VehicleCandidate] {
        // Simulate provider latency.
        try? await Task.sleep(for: .milliseconds(300))

        // Seed the pick on the image bytes so the same photo is stable.
        let seed = imageData.prefix(64).reduce(0) { $0 &+ Int($1) }
        let primary = Self.catalog[seed % Self.catalog.count]
        let secondary = Self.catalog[(seed / 3 + 1) % Self.catalog.count]
        let tertiary = Self.catalog[(seed / 7 + 2) % Self.catalog.count]

        return [
            VehicleCandidate(make: primary.0, model: primary.1,
                             yearEstimate: primary.2, confidence: 0.94),
            VehicleCandidate(make: secondary.0, model: secondary.1,
                             yearEstimate: secondary.2, confidence: 0.61),
            VehicleCandidate(make: tertiary.0, model: tertiary.1,
                             yearEstimate: tertiary.2, confidence: 0.38)
        ]
    }
}
