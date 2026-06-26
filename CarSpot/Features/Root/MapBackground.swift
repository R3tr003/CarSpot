import SwiftUI
import MapKit

/// Full-screen map that lives behind every screen (Flighty-style). Shows the
/// neighbourhoods where cars have been spotted and the routes between them.
struct MapBackground: View {
    /// Shared so the camera stays put while switching tabs.
    @Binding var position: MapCameraPosition

    static let defaultPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.5, longitude: 8.5),
            span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 24)
        )
    )

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(SpotPlace.sample) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    SpotPin(rarity: place.rarity)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls { }   // keep it clean — no default controls
        .ignoresSafeArea()
        .tint(CSColor.accent)
    }
}

/// A glowing spot marker tinted by the rarity found there.
private struct SpotPin: View {
    let rarity: Rarity
    var body: some View {
        ZStack {
            Circle().fill(rarity.primary.opacity(0.25)).frame(width: 26, height: 26).blur(radius: 4)
            Circle().fill(rarity.linearGradient).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
        }
        .shadow(color: rarity.primary.opacity(0.6), radius: 6)
    }
}

/// Sample spotting locations across Europe for the background map.
struct SpotPlace: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let rarity: Rarity
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    static let sample: [SpotPlace] = [
        SpotPlace(name: "Barcelona", latitude: 41.39, longitude: 2.16, rarity: .rara),
        SpotPlace(name: "Madrid", latitude: 40.41, longitude: -3.70, rarity: .comune),
        SpotPlace(name: "Firenze", latitude: 43.77, longitude: 11.25, rarity: .leggendaria),
        SpotPlace(name: "Roma", latitude: 41.90, longitude: 12.49, rarity: .epica),
        SpotPlace(name: "Milano", latitude: 45.46, longitude: 9.19, rarity: .rara)
    ]
}

#Preview { MapBackground(position: .constant(MapBackground.defaultPosition)) }
