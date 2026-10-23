import Foundation
import CoreLocation

/// Requests "when in use" location and exposes the authorization status.
/// The exact position is never displayed in the UI — only the neighbourhood.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus
    /// Vero dopo aver mostrato il prompt di sistema: la prima risposta si traccia una volta.
    private var awaitingAnswer = false

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Ask once. Safe to call repeatedly — the system only prompts when needed.
    func request() {
        if manager.authorizationStatus == .notDetermined {
            awaitingAnswer = true
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let new = manager.authorizationStatus
        if new == .authorizedWhenInUse || new == .authorizedAlways {
            manager.startUpdatingLocation()
        }
        Task { @MainActor in
            self.status = new
            if self.awaitingAnswer, new != .notDetermined {
                self.awaitingAnswer = false
                let granted = new == .authorizedWhenInUse || new == .authorizedAlways
                AppServices.analytics.track(.permissionAnswered(permission: .location, granted: granted))
            }
        }
    }
}
