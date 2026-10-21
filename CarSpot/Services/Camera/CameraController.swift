import AVFoundation
import UIKit
import os

private let cameraLog = Logger(subsystem: "com.carspot.andrea.app", category: "camera")

/// Errori di scatto lato app (quelli di AVFoundation passano così come sono).
enum CameraError: Error {
    case notReady, busy, noData
}

/// Thin AVFoundation wrapper. Exposes an async `capturePhoto()` and a session for
/// the preview layer. On devices without a camera (the simulator) the status is
/// `.unavailable` and the UI falls back to the photo library.
///
/// AVFoundation types aren't `Sendable`; all hardware access is confined to
/// `sessionQueue` and bridged with deliberate `nonisolated(unsafe)` bindings.
@MainActor
@Observable
final class CameraController: NSObject {

    enum Status { case idle, configuring, ready, unavailable, denied }

    private(set) var status: Status = .idle
    /// Vero mentre uno scatto è in volo (il pulsante si disabilita).
    private(set) var isCapturing = false

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    private var captureContinuation: CheckedContinuation<Data, Error>?
    private let sessionQueue = DispatchQueue(label: "com.carspot.camera.session")
    /// Dimensioni di scatto scelte in configurazione (lato lungo ≥ 2016 px, le più piccole).
    private var photoDimensions: CMVideoDimensions?

    var isAvailable: Bool { status == .ready }

    /// Idempotente e riavviabile: configura una sola volta, poi avvia solo la sessione.
    /// Rilegge il permesso se era negato (l'utente può averlo abilitato da Impostazioni).
    func prepare() async {
        switch status {
        case .configuring: return
        case .ready: start(); return
        case .unavailable: return
        case .idle, .denied: break
        }

        // Senza fotocamera (simulatore) non chiediamo nemmeno il permesso.
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            cameraLog.notice("Nessuna fotocamera posteriore disponibile")
            status = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            status = .configuring
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { status = .denied; return }
        default:
            status = .denied
            return
        }

        status = .configuring
        if let dimensions = await configureSession() {
            photoDimensions = dimensions
            status = .ready
            start()
        } else {
            status = .unavailable
        }
    }

    /// Configura input/output. Ritorna le dimensioni di scatto scelte, `nil` se fallisce.
    private func configureSession() async -> CMVideoDimensions? {
        nonisolated(unsafe) let session = self.session
        nonisolated(unsafe) let photoOutput = self.photoOutput
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .photo

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    cameraLog.error("Fotocamera posteriore assente")
                    continuation.resume(returning: nil); return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        cameraLog.error("Impossibile aggiungere l'input video")
                        continuation.resume(returning: nil); return
                    }
                    session.addInput(input)
                } catch {
                    cameraLog.error("Input fotocamera non creato: \(error.localizedDescription)")
                    AppServices.errors.record(error, area: .camera, step: "configure_input")
                    continuation.resume(returning: nil); return
                }
                guard session.canAddOutput(photoOutput) else {
                    cameraLog.error("Impossibile aggiungere l'output foto")
                    continuation.resume(returning: nil); return
                }
                session.addOutput(photoOutput)

                // Scatto più piccolo e veloce: il riconoscimento usa comunque ≤1600 px.
                let dimensions = pickPhotoDimensions(from: device.activeFormat.supportedMaxPhotoDimensions)
                if let dimensions {
                    photoOutput.maxPhotoDimensions = dimensions
                    cameraLog.info("Dimensioni di scatto: \(dimensions.width)x\(dimensions.height)")
                }
                photoOutput.maxPhotoQualityPrioritization = .speed
                continuation.resume(returning: dimensions ?? CMVideoDimensions(width: 0, height: 0))
            }
        }
    }

    func start() {
        nonisolated(unsafe) let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        nonisolated(unsafe) let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Scatta e ritorna i dati grezzi (HEIC/JPEG): nessuna decodifica sul main actor.
    func capturePhoto() async throws -> Data {
        guard status == .ready else { throw CameraError.notReady }
        guard captureContinuation == nil else { throw CameraError.busy }
        isCapturing = true
        defer { isCapturing = false }

        nonisolated(unsafe) let photoOutput = self.photoOutput
        let delegate = self
        nonisolated(unsafe) let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        if let dimensions = photoDimensions, dimensions.width > 0 {
            settings.maxPhotoDimensions = dimensions
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            sessionQueue.async {
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

/// Le dimensioni supportate più piccole con lato lungo ≥ 2016 px (altrimenti le più grandi).
private func pickPhotoDimensions(from supported: [CMVideoDimensions]) -> CMVideoDimensions? {
    func area(_ d: CMVideoDimensions) -> Int64 { Int64(d.width) * Int64(d.height) }
    let enough = supported.filter { max($0.width, $0.height) >= 2016 }
    return enough.min { area($0) < area($1) } ?? supported.max { area($0) < area($1) }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        // Il delegate gira su una coda AVFoundation: estrae il risultato e
        // riprende la continuation (stato main-actor) sul main actor.
        let result: Result<Data, Error>
        if let error {
            cameraLog.error("Scatto fallito: \(error.localizedDescription)")
            AppServices.errors.record(error, area: .camera, step: "capture_photo")
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            cameraLog.error("Scatto senza dati")
            result = .failure(CameraError.noData)
        }
        Task { @MainActor in
            let continuation = captureContinuation
            captureContinuation = nil
            continuation?.resume(with: result)
        }
    }
}
