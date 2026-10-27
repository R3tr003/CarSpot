import Testing
import Foundation
import CoreLocation
@testable import CarSpot

private struct FixedFix: LocationSource {
    var location: CLLocation?
    func currentLocation() async -> CLLocation? { location }
}

private struct NoNames: PlaceNameLookup {
    struct Failure: Error {}
    func placeNames(at location: CLLocation) async throws -> PlaceNames { throw Failure() }
}

@Suite("Coordinate dello scatto (solo locali)")
struct SpotCoordinateTests {
    @Test("coordinate non valide → nil", arguments: [
        (91.0, 0.0), (-91.0, 0.0), (0.0, 181.0), (0.0, -181.0), (.nan, 0.0), (0.0, .infinity),
    ])
    func nonValide(lat: Double, lon: Double) {
        #expect(SpotCoordinate(latitude: lat, longitude: lon) == nil)
    }

    @Test("il risolutore restituisce la coordinata anche se il nome dell'area manca")
    func coordinataSenzaNome() async throws {
        let r = LocationAreaResolver(source: FixedFix(location: CLLocation(latitude: 45.07, longitude: 7.68)),
                                     lookup: NoNames())
        let spot = await r.resolveSpot()
        #expect(spot.area == nil)
        let coordinate = try #require(spot.coordinate)
        #expect(coordinate.latitude == 45.07)
        #expect(coordinate.longitude == 7.68)
    }

    @Test("senza posizione non c'è né area né coordinata")
    func nessunaPosizione() async {
        let r = LocationAreaResolver(source: FixedFix(location: nil), lookup: NoNames())
        #expect(await r.resolveSpot() == ResolvedSpot())
    }

    @Test("un risolutore senza coordinate (Mock di default) non ne inventa")
    func mockSenzaCoordinate() async {
        let spot = await MockAreaResolver(area: "Lungomare").resolveSpot()
        #expect(spot.area == "Lungomare")
        #expect(spot.coordinate == nil)
    }

    @Test("StoredCard: coordinate opzionali, nil di default")
    func carta() throws {
        let card = StoredCard(make: "Fiat", model: "Panda", year: 2020, rarity: .comune, colorName: "Bianca",
                              power: 10, agility: 10, presence: 10, spottedArea: "Centro")
        #expect(card.spotCoordinate == nil)
        card.latitude = 45.07
        #expect(card.spotCoordinate == nil)   // ne serve una coppia
        card.longitude = 7.68
        #expect(try #require(card.spotCoordinate).latitude == 45.07)
    }

    @Test("CloudCard (payload verso Supabase) non contiene mai coordinate")
    func cloudSenzaCoordinate() throws {
        let cloud = CloudCard(id: UUID(), ownerId: "user_x", make: "Fiat", model: "Panda", year: 2020,
                              rarity: "Comune", colorName: "Bianca", power: 1, agility: 1, presence: 1,
                              photoPath: nil, spottedArea: "Centro", capturedAt: .now, isRepeat: false,
                              createdAt: nil)
        let json = try #require(String(data: try JSONEncoder().encode(cloud), encoding: .utf8)).lowercased()
        for forbidden in ["lat", "lon", "lng", "coord", "geo", "location"] {
            #expect(!json.contains(forbidden), "il payload cloud contiene «\(forbidden)»")
        }
    }
}
