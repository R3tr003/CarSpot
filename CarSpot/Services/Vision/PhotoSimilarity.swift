import Foundation
import Vision
import os

private let similarityLog = Logger(subsystem: "com.carspot.andrea.app", category: "vision")

/// Riconosce la "stessa auto" dalla foto: confronto on-device (feature print di Vision) tra la
/// foto appena scattata, già anonimizzata, e le ultime catture dello stesso modello.
/// Non invia nulla: lavora solo su dati già in memoria.
enum PhotoSimilarity {
    /// Distanza massima tra due feature print per considerarle la stessa scena.
    /// Su immagini quasi identiche (stessa auto, stessa inquadratura) Vision dà valori vicini a 0;
    /// scene diverse stanno ben sopra 1. 0,5 è un punto di partenza prudente: meglio perdere
    /// qualche ripetizione che togliere punti a un'auto nuova. DA TARARE SU DEVICE.
    static let maxDistance: Float = 0.5

    /// Quante catture recenti confrontare al massimo (le più recenti dello stesso modello).
    static let maxCandidates = 10

    /// Finestra di ricerca delle catture da confrontare.
    static let lookback: TimeInterval = 7 * 86_400

    /// `true` se `jpeg` è quasi identica a una delle foto in `candidates`.
    /// Errore di Vision → `false`: non si penalizza mai l'utente per un problema tecnico.
    @concurrent
    static func isNearDuplicate(_ jpeg: Data, of candidates: [Data]) async -> Bool {
        guard !candidates.isEmpty else { return false }
        do {
            let reference = try featurePrint(of: jpeg)
            for candidate in candidates.prefix(maxCandidates) {
                if Task.isCancelled { return false }
                // Una foto illeggibile si salta: non invalida il confronto con le altre.
                guard let other = try? featurePrint(of: candidate) else { continue }
                var distance: Float = 0
                guard (try? reference.computeDistance(&distance, to: other)) != nil else { continue }
                if distance <= maxDistance { return true }
            }
            return false
        } catch {
            similarityLog.error("Confronto foto fallito: \(error.localizedDescription)")
            return false
        }
    }

    private enum SimilarityError: Error { case noObservation }

    private static func featurePrint(of jpeg: Data) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: jpeg, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw SimilarityError.noObservation
        }
        return observation
    }
}
