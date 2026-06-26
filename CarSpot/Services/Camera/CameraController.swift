import AVFoundation
import UIKit

/// Thin AVFoundation wrapper. Exposes an async `capturePhoto()` and a session for
/// the preview layer. On devices without a camera (the simulator) `isAvailable`
/// is false and the UI falls back to the photo library.
///
/// AVFoundation types aren't `Sendable`; all hardware access is confined to
/// `sessionQueue` and bridged with deliberate `nonisolated(unsafe)` bindings.
@MainActor
@Observable
final class CameraController: NSObject {

    enum Status { case idle, configuring, ready, unavailable, denied }

    private(set) var status: Status = .idle

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private var captureContinuation: CheckedContinuation<UIImage, Error>?
    private let sessionQueue = DispatchQueue(label: "com.carspot.camera.session")

    var isAvailable: Bool { status == .ready }

    func prepare() async {
        guard status == .idle else { return }
        status = .configuring

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { status = .denied; return }
        default:
            status = .denied; return
        }

        let ok = await configureSession()
        status = ok ? .ready : .unavailable
        if ok { start() }
    }

    private func configureSession() async -> Bool {
        nonisolated(unsafe) let session = self.session
        nonisolated(unsafe) let photoOutput = self.photoOutput
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                defer { session.commitConfiguration() }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    continuation.resume(returning: false); return
                }
                session.addInput(input)
                guard session.canAddOutput(photoOutput) else {
                    continuation.resume(returning: false); return
                }
                session.addOutput(photoOutput)
                continuation.resume(returning: true)
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

    func capturePhoto() async throws -> UIImage {
        nonisolated(unsafe) let photoOutput = self.photoOutput
        nonisolated(unsafe) let delegate = self
        nonisolated(unsafe) let settings = AVCapturePhotoSettings()
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            sessionQueue.async {
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let continuation = captureContinuation
        captureContinuation = nil
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            continuation?.resume(returning: image)
        } else {
            continuation?.resume(throwing: RecognitionError.noMatch)
        }
    }
}
