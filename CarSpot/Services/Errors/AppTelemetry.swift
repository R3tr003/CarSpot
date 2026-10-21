import Foundation
import UIKit
import AVFoundation
import CoreLocation
import Network
import Photos

/// Metriche di ciclo di vita dell'app per le dashboard: avvio, primo piano, durata della
/// sessione, permessi, stato del dispositivo. Passa da `ErrorReporting`, quindi non fa
/// nulla senza consenso statistiche.
///
/// Privacy: nomi statici e attributi solo enumerati (kind, network, permission, status):
/// mai identificativi, posizione o dati dell'utente.
@MainActor
final class AppTelemetry {
    static let shared = AppTelemetry()

    private let errors = AppServices.errors
    private let pathMonitor = NWPathMonitor()
    private let locationProbe = CLLocationManager()
    private var started = false
    /// Vero tra l'attivazione e l'ingresso in background: un alert di sistema
    /// (permessi, Face ID) non apre una nuova sessione.
    private var isForeground = false
    private var hasLaunched = false
    private var sessionStart: ContinuousClock.Instant?
    private var observers: [any NSObjectProtocol] = []

    private init() {}

    /// Da chiamare una volta, prima della prima attivazione (`CarSpotApp.init`).
    func start() {
        guard !started else { return }
        started = true
        pathMonitor.start(queue: DispatchQueue(label: "com.carspot.telemetry.network"))
        observe(UIApplication.didBecomeActiveNotification) { $0.didBecomeActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.didEnterBackground() }
        observe(UIApplication.didReceiveMemoryWarningNotification) { _ in
            AppServices.errors.metric(count: "memory.warning")
        }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (AppTelemetry) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        observers.append(token)
    }

    // MARK: - Ciclo di vita

    private func didBecomeActive() {
        guard !isForeground else { return }
        isForeground = true
        sessionStart = .now

        // "cold": prima attivazione del processo · "warm": ritorno dal background.
        let kind = hasLaunched ? "warm" : "cold"
        hasLaunched = true
        errors.metric(count: "app.launch", attributes: ["kind": .string(kind)])
        errors.metric(count: "app.foreground", attributes: ["network": .string(networkType)])
        reportPermissions()
        reportDeviceState()
    }

    private func didEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        guard let sessionStart else { return }
        self.sessionStart = nil
        let seconds = (ContinuousClock.now - sessionStart).telemetryMilliseconds / 1_000
        errors.metric(distribution: "app.session.duration", value: seconds, unit: .second)
    }

    // MARK: - Rete

    /// wifi | cellular | other (cavo, tethering…) | none.
    private var networkType: String {
        let path = pathMonitor.currentPath
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        return "other"
    }

    // MARK: - Permessi

    private enum Permission: String { case camera, location, photos }
    private enum PermissionStatus: String { case granted, denied, undetermined, limited }

    /// Un gauge per permesso: 1 se l'app può usarlo (granted/limited), 0 altrimenti.
    private func reportPermissions() {
        let statuses: [(Permission, PermissionStatus)] = [
            (.camera, cameraStatus), (.location, locationStatus), (.photos, photosStatus),
        ]
        for (permission, status) in statuses {
            let usable = status == .granted || status == .limited
            errors.metric(gauge: "permission.status", value: usable ? 1 : 0, attributes: [
                "permission": .string(permission.rawValue), "status": .string(status.rawValue),
            ])
        }
    }

    private var cameraStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private var locationStatus: PermissionStatus {
        switch locationProbe.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private var photosStatus: PermissionStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .granted
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    // MARK: - Dispositivo

    /// `device.thermal`: 0 nominal · 1 fair · 2 serious · 3 critical.
    /// `device.low_power`: 1 con il risparmio energetico attivo.
    private func reportDeviceState() {
        let info = ProcessInfo.processInfo
        errors.metric(gauge: "device.thermal", value: Double(info.thermalState.rawValue))
        errors.metric(gauge: "device.low_power", value: info.isLowPowerModeEnabled ? 1 : 0)
    }
}
