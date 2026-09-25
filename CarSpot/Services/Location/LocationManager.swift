import Foundation
import CoreLocation

/// Requests "when in use" location and exposes the authorization status.
/// The exact position is never displayed in the UI — only the neighbourhood.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Ask once. Safe to call repeatedly — the system only prompts when needed.
    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let new = manager.authorizationStatus
        if new == .authorizedWhenInUse || new == .authorizedAlways {
            manager.startUpdatingLocation()
        }
        Task { @MainActor in self.status = new }
    }
}
