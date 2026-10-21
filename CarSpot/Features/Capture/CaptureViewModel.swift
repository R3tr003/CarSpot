import SwiftUI
import SwiftData
import os

private let captureLog = Logger(subsystem: "com.carspot.andrea.app", category: "capture")

/// Etichetta qualitativa della confidenza: la percentuale resta solo per VoiceOver.
enum ConfidenceLevel: Sendable {
    case alta, media, bassa

    init(_ confidence: Double) {
        switch confidence {
        case 0.75...: self = .alta
        case 0.5...: self = .media
        default: self = .bassa
        }
    }

    var label: String {
        switch self {
        case .alta: "Alta"
        case .media: "Media"
        case .bassa: "Bassa"
        }
    }
}

extension VehicleCandidate {
    var confidenceLevel: ConfidenceLevel { ConfidenceLevel(confidence) }
}

/// Codifica la foto da salvare fuori dal main actor.
private enum PhotoPreparation {
    @concurrent
    static func jpeg(from data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return PhotoEncoding.jpeg(image)
    }
}

/// Orchestrates the capture pipeline: image → on-device anonymization →
/// recognition → candidate confirmation → persisted card.
@MainActor
@Observable
final class CaptureViewModel {

    enum Phase: Equatable { case aiming, processing, result, saved }

    /// Cosa fa il bottone "Riprova" del banner d'errore.
    enum Retry: Equatable {
        case dismiss     // torna al mirino
        case recognize   // ripete il riconoscimento sulla stessa immagine
        case save        // ripete il salvataggio
    }

    /// Sotto questa soglia il primo candidato non è preselezionato.
    static let lowConfidenceThreshold = 0.5

    var phase: Phase = .aiming
    var anonymizedImage: UIImage?
    /// Miniatura (non anonimizzata, solo in memoria) per lo sfondo sfocato durante l'elaborazione.
    var previewImage: UIImage?
    var candidates: [VehicleCandidate] = []
    var selected: VehicleCandidate?
    var lastReward = 0
    /// Carta appena salvata, per il reveal.
    private(set) var savedCard: SpotCard?
    /// Messaggio d'errore per l'utente (mai testo tecnico).
    private(set) var errorMessage: String?
    /// Cambia a ogni errore: serve a far ripartire il timer di auto-chiusura.
    private(set) var errorID = 0
    private(set) var errorRetry: Retry = .dismiss

    /// Il primo candidato è sotto soglia: l'utente deve scegliere a mano.
    var isLowConfidence: Bool {
        guard let first = candidates.first else { return false }
        return first.confidence < Self.lowConfidenceThreshold
    }

    private let recognizer: any RecognitionService = AppConfig.makeRecognitionService()
    private let areas = ["Centro Storico", "Lungomare", "Quartiere Nord", "Collina", "Stazione"]

    /// JPEG anonimizzato, tenuto per ripetere il riconoscimento senza rifare la pipeline.
    private var safeData: Data?
    /// Foto da salvare, già codificata in background durante il riconoscimento.
    private var photoJPEG: Data?
    private var photoTask: Task<Void, Never>?

    /// Pipeline su un'immagine già in memoria (percorso debug `-autoCapture`).
    /// `source` è solo per le statistiche: "camera" | "library" | "auto".
    func process(image: UIImage, source: String = "camera") async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            fail(.photoUnreadable); return
        }
        await process(data: data, source: source)
    }

    /// Run the full pipeline on raw captured/picked data (HEIC/JPEG).
    /// Decodifica, riduzione e codifica girano fuori dal main actor.
    func process(data: Data, source: String = "camera") async {
        AppServices.analytics.track(.captureStarted(source: source))
        clearCapture()
        errorMessage = nil
        phase = .processing

        // 0. Riduzione ImageIO (≤1600 px) + miniatura per il fermo-immagine sfocato.
        guard let prepared = await ImageDownsampler.prepare(data: data) else {
            AppServices.errors.breadcrumb("Foto non decodificabile", area: .capture)
            fail(.photoUnreadable); return
        }
        previewImage = UIImage(data: prepared.thumbnail)

        // 1. Anonymize on-device BEFORE anything else touches the photo.
        let safe = await ImageAnonymizer.anonymize(jpegData: prepared.jpeg)
        anonymizedImage = UIImage(data: safe)
        safeData = safe

        // La foto da salvare si codifica in parallelo al riconoscimento (fuori dal main actor).
        photoTask = Task { [weak self] in
            let jpeg = await PhotoPreparation.jpeg(from: safe)
            self?.photoJPEG = jpeg
        }

        // 2. Recognize (mock offline, or Supabase Edge Function when configured).
        await recognize(safe)
    }

    private func recognize(_ data: Data) async {
        do {
            let result = try await recognizer.recognize(imageData: data)
            guard !result.isEmpty else {
                fail(.noVehicleFound); return
            }
            candidates = result
            // Con bassa confidenza nessuna preselezione: sceglie l'utente.
            selected = isLowConfidence ? nil : result.first
            phase = .result
            announceResults(result)
        } catch {
            captureLog.error("Riconoscimento fallito: \(error.localizedDescription)")
            // Ripetere ha senso per rete/server; "nessuna auto" richiede un'altra foto.
            var retry = Retry.recognize
            if case RecognitionError.noMatch = error {
                retry = .dismiss
            } else {
                AppServices.errors.record(error, area: .recognition, step: "recognize")
            }
            fail(AppError.message(for: error, fallback: .recognitionFailed), retry: retry)
        }
    }

    /// Persist the confirmed candidate as a collectible.
    func save(into context: ModelContext) {
        guard let candidate = selected else { return }
        let year = candidate.yearEstimate ?? Calendar.current.component(.year, from: .now)
        let a = RarityEngine.assess(make: candidate.make, model: candidate.model, year: year)
        // Se la codifica in background non è ancora pronta (raro) si ricade su quella locale.
        let photo = photoJPEG ?? anonymizedImage.flatMap { PhotoEncoding.jpeg($0) }
        let card = StoredCard(
            make: candidate.make, model: candidate.model, year: year,
            rarity: a.rarity, colorName: a.colorName,
            power: a.power, agility: a.agility, presence: a.presence,
            spottedArea: areas.randomElement() ?? "Centro",
            photo: photo
        )
        context.insert(card)
        do {
            try context.save()
        } catch {
            // Niente stato "salvata" se la scrittura è fallita.
            context.delete(card)
            captureLog.error("Salvataggio carta fallito: \(error.localizedDescription)")
            AppServices.errors.record(error, area: .capture, step: "save_card")
            showError(AppError.message(for: error, fallback: .saveCardFailed), retry: .save)
            return
        }
        // Award XP/currency for the catch.
        PlayerStore.award(xp: a.rarity.xpReward, currency: a.rarity.currencyReward, in: context)
        lastReward = a.rarity.xpReward
        // Invio al cloud in background (no-op se sync spento o utente non loggato).
        if let sync = SyncService.shared { Task { await sync.didSave(card) } }
        // Nome del case (es. "leggendaria"), stabile e indipendente dalla lingua.
        AppServices.analytics.track(.cardSaved(rarity: String(describing: a.rarity)))
        errorMessage = nil
        savedCard = card.asSpotCard
        phase = .saved
        AccessibilityNotification.Announcement(
            "Aggiunta alla collezione: \(candidate.title), \(a.rarity.rawValue)"
        ).post()
    }

    func reset() {
        clearCapture()
        candidates = []
        selected = nil
        savedCard = nil
        errorMessage = nil
        phase = .aiming
    }

    // MARK: Errori

    /// Errori a copy fisso segnalati dalla view (scatto, lettura foto).
    func report(_ error: AppError) {
        showError(error.message)
    }

    /// Chiude il banner (timer o tap) senza ripetere nulla.
    func dismissError() {
        errorMessage = nil
        if phase == .aiming { clearCapture() }
    }

    /// "Riprova" del banner: ripete l'ultima operazione o torna al mirino.
    func retry(into context: ModelContext) async {
        let kind = errorRetry
        errorMessage = nil
        switch kind {
        case .recognize:
            guard let data = safeData else { dismissError(); return }
            phase = .processing
            await recognize(data)
        case .save:
            save(into: context)
        case .dismiss:
            if phase == .aiming { clearCapture() }
        }
    }

    private func fail(_ error: AppError, retry: Retry = .dismiss) {
        fail(error.message, retry: retry)
    }

    private func fail(_ message: String, retry: Retry = .dismiss) {
        showError(message, retry: retry)
        // Il riconoscimento ripetibile conserva la miniatura per il fermo-immagine.
        if retry != .recognize { previewImage = nil }
        phase = .aiming
    }

    private func showError(_ message: String, retry: Retry = .dismiss) {
        errorID += 1
        errorMessage = message
        errorRetry = retry
        AccessibilityNotification.Announcement(message).post()
    }

    private func clearCapture() {
        photoTask?.cancel()
        photoTask = nil
        photoJPEG = nil
        safeData = nil
        anonymizedImage = nil
        previewImage = nil
    }

    // MARK: Copy

    private func announceResults(_ result: [VehicleCandidate]) {
        guard let first = result.first else { return }
        var text = result.count == 1
            ? "Trovata una corrispondenza: \(first.title)."
            : "Trovate \(result.count) corrispondenze, la prima: \(first.title)."
        if isLowConfidence { text += " Non siamo sicuri, scegli quella giusta." }
        AccessibilityNotification.Announcement(text).post()
    }
}
