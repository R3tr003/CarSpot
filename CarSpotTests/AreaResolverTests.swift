import Testing
import CoreLocation
@testable import CarSpot

/// Posizione/lookup finti: nessuna rete, nessun GPS.
private struct FixedLocation: LocationSource {
    var location: CLLocation?
    func currentLocation() async -> CLLocation? { location }
}

private struct StubLookup: PlaceNameLookup {
    struct Failure: Error {}
    var names: PlaceNames?
    func placeNames(at location: CLLocation) async throws -> PlaceNames {
        guard let names else { throw Failure() }
        return names
    }
}

/// Resta in attesa finché non viene annullato (simula GPS/rete che non rispondono).
private struct HangingLocation: LocationSource {
    func currentLocation() async -> CLLocation? {
        try? await Task.sleep(for: .seconds(60))
        return nil
    }
}

private let somewhere = CLLocation(latitude: 45.07, longitude: 7.68)

private func resolver(location: CLLocation? = somewhere, names: PlaceNames?) -> LocationAreaResolver {
    LocationAreaResolver(source: FixedLocation(location: location), lookup: StubLookup(names: names))
}

@Suite("PlaceNames.areaName")
struct PlaceNamesTests {
    @Test("quartiere → città → nil", arguments: [
        (PlaceNames(neighbourhood: "Vanchiglia", city: "Torino"), "Vanchiglia"),
        (PlaceNames(neighbourhood: nil, city: "Torino"), "Torino"),
        (PlaceNames(neighbourhood: "", city: "Torino"), "Torino"),
        (PlaceNames(neighbourhood: "  \n", city: "Torino"), "Torino"),
        (PlaceNames(neighbourhood: "  Vanchiglia ", city: nil), "Vanchiglia"),
    ])
    func preferenza(names: PlaceNames, expected: String) {
        #expect(names.areaName == expected)
    }

    @Test("nessun nome utilizzabile → nil")
    func vuoto() {
        #expect(PlaceNames().areaName == nil)
        #expect(PlaceNames(neighbourhood: " ", city: "").areaName == nil)
    }
}

@Suite("LocationAreaResolver")
struct LocationAreaResolverTests {
    @Test("usa il quartiere se c'è")
    func quartiere() async {
        let r = resolver(names: PlaceNames(neighbourhood: "Vanchiglia", city: "Torino"))
        #expect(await r.resolveArea() == "Vanchiglia")
    }

    @Test("senza quartiere ripiega sulla città")
    func citta() async {
        let r = resolver(names: PlaceNames(neighbourhood: nil, city: "Torino"))
        #expect(await r.resolveArea() == "Torino")
    }

    @Test("nessun nome → nil (fallback al chiamante)")
    func nessunNome() async {
        #expect(await resolver(names: PlaceNames()).resolveArea() == nil)
    }

    @Test("senza fix (permesso negato) → nil, senza chiamare il geocoder")
    func senzaPosizione() async {
        let r = resolver(location: nil, names: PlaceNames(neighbourhood: "Mai usato", city: nil))
        #expect(await r.resolveArea() == nil)
    }

    @Test("errore del geocoder → nil")
    func erroreGeocoder() async {
        #expect(await resolver(names: nil).resolveArea() == nil)
    }

    @Test("GPS che non risponde → nil entro il timeout")
    func timeout() async {
        let r = LocationAreaResolver(
            source: HangingLocation(), lookup: StubLookup(names: PlaceNames(city: "Torino")),
            locationTimeout: .milliseconds(50))
        #expect(await r.resolveArea() == nil)
    }

    @Test("il mock restituisce l'area impostata")
    func mock() async {
        #expect(await MockAreaResolver(area: "Lungomare").resolveArea() == "Lungomare")
        #expect(await MockAreaResolver(area: nil).resolveArea() == nil)
    }
}
