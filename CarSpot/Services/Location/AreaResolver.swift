import Foundation
import CoreLocation
import MapKit
import os

private let areaLog = Logger(subsystem: "com.carspot.andrea.app", category: "area")

/// Nomi di luogo grossolani ricavati da una posizione. Mai coordinate.
struct PlaceNames: Sendable, Equatable {
    var neighbourhood: String?
    var city: String?

    /// Quartiere, altrimenti città; stringhe vuote o di soli spazi contano come assenti.
    var areaName: String? {
        Self.clean(neighbourhood) ?? Self.clean(city)
    }

    private static func clean(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Coordinata esatta di uno scatto. Resta SOLO sul dispositivo (`StoredCard`): mai nel
/// cloud, negli eventi di analytics o nei log. Tipo proprio per non portarsi dietro `CLLocation`.
struct SpotCoordinate: Sendable, Equatable {
    let latitude: Double
    let longitude: Double

    /// `nil` se la coppia non è una coordinata valida (NaN, fuori range).
    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    init?(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

/// Dove è stato fatto uno scatto: il nome dell'area (può andare al cloud) e, a parte,
/// la coordinata esatta (solo locale).
struct ResolvedSpot: Sendable, Equatable {
    var area: String?
    var coordinate: SpotCoordinate?
}

/// Ricava il nome dell'area dove si trova l'utente ora. `nil` = non disponibile
/// (niente permesso, nessun fix, offline, errore): il chiamante usa il fallback.
/// Dal nome dell'area non si risale alla posizione; la coordinata esatta esce solo da
/// `resolveSpot()` e il chiamante la salva unicamente sul dispositivo.
protocol AreaResolving: Sendable {
    func resolveArea() async -> String?
    func resolveSpot() async -> ResolvedSpot
}

extension AreaResolving {
    /// Implementazioni senza coordinate (test, anteprime): solo l'area.
    func resolveSpot() async -> ResolvedSpot {
        ResolvedSpot(area: await resolveArea(), coordinate: nil)
    }
}

/// Posizione corrente one-shot.
protocol LocationSource: Sendable {
    func currentLocation() async -> CLLocation?
}

/// Reverse geocoding verso nomi di luogo.
protocol PlaceNameLookup: Sendable {
    func placeNames(at location: CLLocation) async throws -> PlaceNames
}

/// Posizione → nome dell'area, con tetto di tempo su ogni passo di rete/GPS
/// così non allunga mai la cattura.
struct LocationAreaResolver: AreaResolving {
    var source: any LocationSource = OneShotLocationSource()
    var lookup: any PlaceNameLookup = MapKitPlaceNameLookup()
    var locationTimeout: Duration = .seconds(4)
    var lookupTimeout: Duration = .seconds(4)

    func resolveArea() async -> String? {
        await resolveSpot().area
    }

    func resolveSpot() async -> ResolvedSpot {
        let source = source, lookup = lookup
        guard let location = await Self.first(within: locationTimeout, { await source.currentLocation() }) else {
            areaLog.info("Area non risolta: nessuna posizione")
            return ResolvedSpot()
        }
        // La coordinata c'è anche se il nome dell'area non si trova.
        let coordinate = SpotCoordinate(location)
        let names = await Self.first(within: lookupTimeout) { () async -> PlaceNames? in
            do {
                return try await lookup.placeNames(at: location)
            } catch {
                // Niente dettagli: l'errore di geocoding può contenere la richiesta.
                areaLog.error("Reverse geocoding fallito: \(type(of: error))")
                return nil
            }
        }
        guard let area = names?.areaName else {
            areaLog.info("Area non risolta: nessun nome di luogo")
            return ResolvedSpot(area: nil, coordinate: coordinate)
        }
        return ResolvedSpot(area: area, coordinate: coordinate)
    }

    /// Risultato di `operation`, oppure `nil` se scade prima il tempo.
    private static func first<T: Sendable>(
        within limit: Duration, _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

/// Posizione fissa (o assente) per test, anteprime e simulatore senza GPS.
struct MockAreaResolver: AreaResolving {
    var area: String?
    var coordinate: SpotCoordinate?
    func resolveArea() async -> String? { area }
    func resolveSpot() async -> ResolvedSpot { ResolvedSpot(area: area, coordinate: coordinate) }
}

// MARK: Implementazioni di sistema

/// Primo fix disponibile, solo con permesso "quando in uso" già concesso:
/// non mostra mai il prompt (lo gestisce l'onboarding).
struct OneShotLocationSource: LocationSource {
    func currentLocation() async -> CLLocation? {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: return nil
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            }
        } catch {
            areaLog.error("Posizione non disponibile: \(type(of: error))")
        }
        return nil
    }
}

/// Reverse geocoding con MapKit (iOS 26: sostituisce `CLGeocoder`, deprecato).
struct MapKitPlaceNameLookup: PlaceNameLookup {
    func placeNames(at location: CLLocation) async throws -> PlaceNames {
        guard let request = MKReverseGeocodingRequest(location: location) else { return PlaceNames() }
        guard let item = try await request.mapItems.first else { return PlaceNames() }
        return PlaceNames(
            neighbourhood: Self.neighbourhood(of: item),
            city: item.addressRepresentations?.cityName)
    }

    /// Le nuove API (`address`, `addressRepresentations`) non espongono il quartiere:
    /// l'unico accesso è `placemark.subLocality`, deprecato in iOS 26. Isolato qui.
    @available(iOS, deprecated: 26.0, message: "MapKit non ha ancora un equivalente per il quartiere")
    private static func neighbourhood(of item: MKMapItem) -> String? {
        item.placemark.subLocality
    }
}
