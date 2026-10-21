import SwiftUI
import SwiftData

/// Orchestrates the capture pipeline: image → on-device anonymization →
/// recognition → candidate confirmation → persisted card.
@MainActor
@Observable
final class CaptureViewModel {

    enum Phase: Equatable { case aiming, processing, result, saved }

    var phase: Phase = .aiming
    var anonymizedImage: UIImage?
    var candidates: [VehicleCandidate] = []
    var selected: VehicleCandidate?
    var errorMessage: String?
    var lastReward = 0

    private let recognizer: any RecognitionService = AppConfig.makeRecognitionService()
    private let areas = ["Centro Storico", "Lungomare", "Quartiere Nord", "Collina", "Stazione"]

    /// Run the full pipeline on a freshly captured/picked image.
    /// `source` è solo per le statistiche: "camera" | "library" | "auto".
    func process(image: UIImage, source: String = "camera") async {
        AppServices.analytics.track(.captureStarted(source: source))
        errorMessage = nil
        phase = .processing

        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            fail("Immagine non valida."); return
        }

        // 1. Anonymize on-device BEFORE anything else touches the photo.
        let safeData = await ImageAnonymizer.anonymize(jpegData: jpeg)
        anonymizedImage = UIImage(data: safeData)

        // 2. Recognize (mock offline, or Supabase Edge Function when configured).
        do {
            let result = try await recognizer.recognize(imageData: safeData)
            guard !result.isEmpty else { fail(RecognitionError.noMatch.localizedDescription); return }
            candidates = result
            selected = result.first
            phase = .result
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Persist the confirmed candidate as a collectible.
    func save(into context: ModelContext) {
        guard let candidate = selected else { return }
        let year = candidate.yearEstimate ?? Calendar.current.component(.year, from: .now)
        let a = RarityEngine.assess(make: candidate.make, model: candidate.model, year: year)
        let card = StoredCard(
            make: candidate.make, model: candidate.model, year: year,
            rarity: a.rarity, colorName: a.colorName,
            power: a.power, agility: a.agility, presence: a.presence,
            spottedArea: areas.randomElement() ?? "Centro",
            photo: anonymizedImage.flatMap { PhotoEncoding.jpeg($0) }
        )
        context.insert(card)
        try? context.save()
        // Award XP/currency for the catch.
        PlayerStore.award(xp: a.rarity.xpReward, currency: a.rarity.currencyReward, in: context)
        lastReward = a.rarity.xpReward
        // Invio al cloud in background (no-op se sync spento o utente non loggato).
        if let sync = SyncService.shared { Task { await sync.didSave(card) } }
        // Nome del case (es. "leggendaria"), stabile e indipendente dalla lingua.
        AppServices.analytics.track(.cardSaved(rarity: String(describing: a.rarity)))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        phase = .saved
    }

    func reset() {
        anonymizedImage = nil
        candidates = []
        selected = nil
        errorMessage = nil
        phase = .aiming
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .aiming
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
