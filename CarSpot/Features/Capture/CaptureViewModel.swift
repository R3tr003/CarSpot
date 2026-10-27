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

    var label: LocalizedStringKey {
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

/// Cosa mostra il reveal dopo il salvataggio: nuova / doppione / stessa auto, e la ricompensa.
struct RevealInfo: Equatable, Sendable {
    /// Stessa auto già catturata (stesso posto o foto quasi identica): 0 punti.
    let isRepeat: Bool
    /// Posizione di questa carta tra le copie del modello (1 = nuova). Solo tra le non ripetute.
    let copyNumber: Int
    /// Totale delle carte (non ripetute) in collezione dopo il salvataggio.
    let cardNumber: Int
    /// Prima carta di questa marca.
    let isNewMake: Bool
    let xpGained: Int
    let levelBefore: Int
    let levelAfter: Int
    /// Avanzamento nel livello (0...1) prima e dopo l'assegnazione dei punti.
    let fractionBefore: Double
    let fractionAfter: Double
    /// Punti dentro il livello dopo la cattura, e quanti ne servono per il successivo.
    let xpInLevel: Int
    let xpForLevel: Int

    var isDuplicate: Bool { !isRepeat && copyNumber > 1 }
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
        case anonymize   // ripete l'anonimizzazione sulla stessa foto
        case recognize   // ripete il riconoscimento sulla stessa immagine
        case save        // ripete il salvataggio
    }

    /// Sotto questa soglia il primo candidato non è preselezionato.
    static let lowConfidenceThreshold = 0.5

    var phase: Phase = .aiming
    var anonymizedImage: UIImage?
    /// Miniatura per lo sfondo sfocato durante l'elaborazione: solo dal JPEG già anonimizzato,
    /// quindi `nil` finché l'anonimizzazione non è finita.
    var previewImage: UIImage?
    var candidates: [VehicleCandidate] = []
    var selected: VehicleCandidate?
    var lastReward = 0
    /// Carta appena salvata, per il reveal.
    private(set) var savedCard: SpotCard?
    /// Dettagli del reveal (nuova/doppione/ripetizione, ricompensa).
    private(set) var revealInfo: RevealInfo?
    /// Salvataggio in corso (il confronto foto è asincrono): evita il doppio tocco.
    private(set) var isSaving = false
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
    private let areaResolver: any AreaResolving = LocationAreaResolver()
    /// Quartiere/città dello scatto, risolto in parallelo alla pipeline (solo il nome, mai coordinate).
    private var spottedArea: String?
    /// Posizione esatta dello scatto: solo per `StoredCard` (dispositivo), mai in cloud/log/analytics.
    private var spottedCoordinate: SpotCoordinate?
    private var areaTask: Task<Void, Never>?
    /// Attesa massima, al salvataggio, del risultato di area/posizione ancora in corso.
    private static let spotWait: Duration = .seconds(1)

    /// Esito della pipeline per le metriche: valori enumerati e stabili.
    private enum Outcome: String {
        case success, noVehicle = "no_vehicle", unreadable
        case recognitionFailed = "recognition_failed", offline, cancelled, error
    }

    /// Da dove arriva la foto. Per le metriche vale `rawValue` (l'auto-capture di debug è camera);
    /// la posizione dello scatto si salva solo per la camera.
    private enum CaptureSource: String {
        case camera, library
    }
    private var captureSource = CaptureSource.camera
    /// Inizio della pipeline in corso (o del riconoscimento ripetuto).
    private var pipelineStart = ContinuousClock.now

    /// JPEG ridotto ma NON anonimizzato, solo in memoria: serve a ripetere l'anonimizzazione
    /// se fallisce. Mai mostrato, salvato né inviato; si azzera appena l'anonimizzazione riesce.
    private var pendingData: Data?
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
        // Un'unica transazione per la pipeline; i passi interni sono span figli.
        await AppServices.errors.measure("capture.pipeline", operation: "capture") {
            await runPipeline(data: data, source: source)
        }
    }

    private func runPipeline(data: Data, source: String) async {
        AppServices.analytics.track(.captureStarted(source: source))
        captureSource = source == "library" ? .library : .camera
        pipelineStart = .now
        AppServices.errors.metric(count: "capture.started")
        clearCapture()
        errorMessage = nil
        phase = .processing

        // Area dello scatto: parte subito e viaggia in parallelo (non blocca nulla).
        areaTask = Task { [weak self, areaResolver] in
            let spot = await areaResolver.resolveSpot()
            guard !Task.isCancelled else { return }
            self?.spottedArea = spot.area
            self?.spottedCoordinate = spot.coordinate
        }

        // 0. Riduzione ImageIO (≤1600 px). Nessuna miniatura finché la foto non è anonimizzata.
        let preparedImage = await AppServices.errors.measure("capture.prepare", operation: "capture") {
            await ImageDownsampler.prepare(data: data)
        }
        guard let prepared = preparedImage else {
            AppServices.errors.breadcrumb("Foto non decodificabile", area: .capture)
            finish(.unreadable)
            fail(.photoUnreadable); return
        }
        pendingData = prepared
        await anonymizeAndRecognize(prepared)
    }

    /// Fail-closed: se l'anonimizzazione non riesce non si riconosce né si salva nulla.
    private func anonymizeAndRecognize(_ prepared: Data) async {
        // 1. Anonymize on-device BEFORE anything else touches the photo.
        let safe: Data
        do {
            safe = try await AppServices.errors.measure("capture.anonymize", operation: "capture") {
                try await ImageAnonymizer.anonymize(jpegData: prepared)
            }
        } catch {
            captureLog.error("Anonimizzazione fallita")
            AppServices.errors.record(error, area: .vision, step: "anonymize")
            finish(.error)
            fail(.anonymizationFailed, retry: .anonymize); return
        }
        pendingData = nil
        anonymizedImage = UIImage(data: safe)
        safeData = safe

        // Miniatura per il fermo-immagine: dal JPEG anonimizzato, mai dall'originale.
        if let thumb = await ImageDownsampler.thumbnail(from: safe) {
            previewImage = UIImage(data: thumb)
        }

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
            let result = try await AppServices.errors.measure("capture.recognize", operation: "capture") {
                try await recognizer.recognize(imageData: data)
            }
            guard !result.isEmpty else {
                finish(.noVehicle)
                fail(.noVehicleFound); return
            }
            candidates = result
            // Con bassa confidenza nessuna preselezione: sceglie l'utente.
            selected = isLowConfidence ? nil : result.first
            phase = .result
            if let top = result.first {
                AppServices.errors.metric(distribution: "recognition.confidence", value: top.confidence)
            }
            finish(.success, candidates: result.count)
            announceResults(result)
        } catch {
            captureLog.error("Riconoscimento fallito: \(error.localizedDescription)")
            // Ripetere ha senso per rete/server; "nessuna auto" richiede un'altra foto.
            finish(Self.outcome(for: error))
            var retry = Retry.recognize
            if case RecognitionError.noMatch = error {
                retry = .dismiss
            } else {
                AppServices.errors.record(error, area: .recognition, step: "recognize")
            }
            fail(AppError.shown(for: error, fallback: .recognitionFailed), retry: retry)
        }
    }

    /// Persist the confirmed candidate as a collectible.
    func save(into context: ModelContext) async {
        guard phase == .result, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        // Fuori dalla pipeline (l'utente conferma dopo): transazione propria.
        await AppServices.errors.measure("capture.save", operation: "capture") {
            await persist(into: context)
        }
    }

    private func persist(into context: ModelContext) async {
        guard let candidate = selected else { return }
        let year = candidate.yearEstimate ?? Calendar.current.component(.year, from: .now)
        let a = AppServices.errors.measureSync("capture.rarity", operation: "capture") {
            RarityEngine.assess(make: candidate.make, model: candidate.model, year: year)
        }
        // Se la codifica in background non è ancora pronta (raro) si ricade su quella locale.
        let photo = photoJPEG ?? anonymizedImage.flatMap { PhotoEncoding.jpeg($0) }
        // Area e posizione partono all'inizio della pipeline: di solito sono già pronte; se no
        // si aspetta un attimo (tetto breve, il salvataggio non resta mai appeso al GPS).
        await awaitSpot(upTo: Self.spotWait)
        // Nel frattempo l'utente può aver annullato: `clearCapture()` ha azzerato tutto.
        guard phase == .result else { return }
        let area = spottedArea ?? String(localized: "Zona sconosciuta")
        let coordinate = spottedCoordinate
        let capturedAt = Date.now
        let card = StoredCard(
            make: candidate.make, model: candidate.model, year: year,
            rarity: a.rarity, colorName: a.colorName,
            power: a.power, agility: a.agility, presence: a.presence,
            spottedArea: area, capturedAt: capturedAt,
            photo: photo
        )

        // Carte esistenti, solo i campi leggeri (le foto si caricano a parte, se servono).
        var lightFetch = FetchDescriptor<StoredCard>()
        lightFetch.propertiesToFetch = [\.make, \.model, \.capturedAt, \.spottedArea, \.isRepeat]
        let existing = (try? context.fetch(lightFetch)) ?? []

        // Ripetizione: stesso modello nello stesso quartiere nelle 24 h (contando anche le
        // ripetizioni, come il trigger server) oppure foto quasi identica a una recente.
        var isRepeat = CardCopies.isRepeatByPlace(
            make: candidate.make, model: candidate.model, area: area, capturedAt: capturedAt,
            among: existing.map { (make: $0.make, model: $0.model, area: $0.spottedArea, capturedAt: $0.capturedAt) })
        if !isRepeat, let photo {
            let target = CardCopies.key(make: candidate.make, model: candidate.model)
            let cutoff = capturedAt.addingTimeInterval(-PhotoSimilarity.lookback)
            let recent = existing
                .filter { $0.capturedAt >= cutoff && CardCopies.key(make: $0.make, model: $0.model) == target }
                .sorted { $0.capturedAt > $1.capturedAt }
                .prefix(PhotoSimilarity.maxCandidates)
                .compactMap(\.photo)
            isRepeat = await PhotoSimilarity.isNearDuplicate(photo, of: recent)
            // Nel frattempo l'utente può aver annullato ("Riprova", X): non si salva più nulla.
            guard phase == .result else { return }
        }
        card.isRepeat = isRepeat
        // Una foto dalla libreria non è stata scattata qui: la posizione di adesso sarebbe falsa.
        if captureSource == .camera, let spot = coordinate {
            card.latitude = spot.latitude
            card.longitude = spot.longitude
        }

        // Numeri del reveal, calcolati prima dell'inserimento e solo tra le non ripetute.
        let counted = existing.filter { !$0.isRepeat }
        let makeKey = CardCopies.key(make: candidate.make, model: "")   // confronto solo sulla marca
        let isNewMake = !counted.contains { CardCopies.key(make: $0.make, model: "") == makeKey }
        let copyNumber = isRepeat ? 1 : CardCopies.copyNumber(
            make: candidate.make, model: candidate.model, capturedAt: capturedAt,
            among: counted.map { (make: $0.make, model: $0.model, capturedAt: $0.capturedAt) })
        let xp = isRepeat ? 0 : CardCopies.xp(base: a.rarity.xpReward, copyNumber: copyNumber)
        let currency = xp / 4
        let isFirstCard = existing.isEmpty

        context.insert(card)
        do {
            try context.save()
        } catch {
            // Niente stato "salvata" se la scrittura è fallita.
            context.delete(card)
            captureLog.error("Salvataggio carta fallito: \(error.localizedDescription)")
            AppServices.errors.record(error, area: .capture, step: "save_card")
            showError(AppError.shown(for: error, fallback: .saveCardFailed), retry: .save)
            return
        }

        // Award XP/currency for the catch (mai per una ripetizione).
        let before = LevelSystem.progress(forXP: PlayerStore.profile(context).xp)
        if !isRepeat {
            PlayerStore.award(xp: xp, currency: currency, in: context)
        }
        let after = LevelSystem.progress(forXP: PlayerStore.profile(context).xp)
        lastReward = xp
        revealInfo = RevealInfo(
            isRepeat: isRepeat, copyNumber: copyNumber,
            cardNumber: counted.count + (isRepeat ? 0 : 1), isNewMake: isNewMake, xpGained: xp,
            levelBefore: before.level, levelAfter: after.level,
            fractionBefore: before.fraction, fractionAfter: after.fraction,
            xpInLevel: after.into, xpForLevel: after.needed)

        // Invio al cloud in background (no-op se sync spento o utente non loggato).
        if let sync = SyncService.shared { Task { await sync.didSave(card) } }
        // Nome del case (es. "leggendaria"), stabile e indipendente dalla lingua.
        AppServices.analytics.track(.cardSaved(
            rarity: String(describing: a.rarity), make: candidate.make,
            isFirstCard: isFirstCard, isNewMake: isNewMake, xpGained: xp))
        AppServices.errors.metric(count: "card.saved", attributes: ["rarity": .string(String(describing: a.rarity))])
        errorMessage = nil
        savedCard = card.asSpotCard
        phase = .saved
        let spoken = isRepeat
            ? String(localized: "Già vista qui: \(candidate.title), nessun punto")
            : String(localized: "Aggiunta alla collezione: \(candidate.title), \(a.rarity.localizedName)")
        AccessibilityNotification.Announcement(spoken).post()
    }

    func reset() {
        clearCapture()
        candidates = []
        selected = nil
        savedCard = nil
        revealInfo = nil
        errorMessage = nil
        phase = .aiming
    }

    // MARK: Metriche

    /// Esito (e durata) della pipeline. Un riconoscimento ripetuto conta come nuovo esito.
    private func finish(_ outcome: Outcome, candidates: Int = 0) {
        let elapsed = ContinuousClock.now - pipelineStart
        let ms = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        let attributes: TelemetryAttributes = [
            "outcome": .string(outcome.rawValue), "source": .string(captureSource.rawValue),
        ]
        AppServices.errors.metric(count: "capture.outcome", attributes: attributes)
        // L'annullamento non è un esito di prodotto: non si traccia.
        if let analyticsOutcome = AnalyticsCaptureOutcome(rawValue: outcome.rawValue) {
            AppServices.analytics.track(.captureCompleted(
                outcome: analyticsOutcome, source: captureSource.rawValue,
                durationMs: Int(ms.rounded()), candidates: candidates))
        }
        AppServices.errors.metric(distribution: "capture.duration", value: ms, unit: .millisecond,
                                  attributes: ["outcome": .string(outcome.rawValue)])
        AppServices.errors.log("capture finished", level: outcome == .error ? .error : .info, attributes: [
            "outcome": .string(outcome.rawValue), "source": .string(captureSource.rawValue),
            "duration_ms": .int(Int(ms.rounded())), "candidates": .int(candidates),
        ])
    }

    /// Esito dal tipo di errore del riconoscimento, senza leggerne il contenuto.
    private static func outcome(for error: any Error) -> Outcome {
        let summary = ErrorSummary(error)
        if summary.isCancellation { return .cancelled }
        if summary.isConnectivity { return .offline }
        if let recognition = error as? RecognitionError {
            switch recognition {
            case .noMatch: return .noVehicle
            case .network, .unauthorized, .rateLimited: return .recognitionFailed
            }
        }
        return .error
    }

    // MARK: Errori

    /// Errori a copy fisso segnalati dalla view (scatto, lettura foto).
    func report(_ error: AppError) {
        showError(error.shown())
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
            pipelineStart = .now
            await recognize(data)
        case .anonymize:
            guard let data = pendingData else { dismissError(); return }
            phase = .processing
            pipelineStart = .now
            await anonymizeAndRecognize(data)
        case .save:
            await save(into: context)
        case .dismiss:
            if phase == .aiming { clearCapture() }
        }
    }

    private func fail(_ error: AppError, retry: Retry = .dismiss) {
        fail(error.shown(), retry: retry)
    }

    private func fail(_ message: String, retry: Retry = .dismiss) {
        showError(message, retry: retry)
        // Il riconoscimento ripetibile conserva la miniatura (già anonimizzata) per il fermo-immagine.
        if retry != .recognize { previewImage = nil }
        phase = .aiming
    }

    private func showError(_ message: String, retry: Retry = .dismiss) {
        errorID += 1
        errorMessage = message
        errorRetry = retry
        AccessibilityNotification.Announcement(message).post()
    }

    /// Aspetta che `areaTask` finisca, ma non oltre `limit`. Non lo annulla: se scade il
    /// risultato arriva dopo e viene ignorato (la carta si salva senza posizione).
    private func awaitSpot(upTo limit: Duration) async {
        guard let task = areaTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    private func clearCapture() {
        photoTask?.cancel()
        photoTask = nil
        areaTask?.cancel()
        areaTask = nil
        spottedArea = nil
        spottedCoordinate = nil
        photoJPEG = nil
        pendingData = nil
        safeData = nil
        anonymizedImage = nil
        previewImage = nil
    }

    // MARK: Copy

    private func announceResults(_ result: [VehicleCandidate]) {
        guard let first = result.first else { return }
        var text = result.count == 1
            ? String(localized: "Trovata una corrispondenza: \(first.title).")
            : String(localized: "Trovate \(result.count) corrispondenze, la prima: \(first.title).")
        if isLowConfidence { text += " " + String(localized: "Non siamo sicuri, scegli quella giusta.") }
        AccessibilityNotification.Announcement(text).post()
    }
}
