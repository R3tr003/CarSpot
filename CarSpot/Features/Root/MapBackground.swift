import SwiftUI
import MapKit

/// Holds the ONE shared `MKMapView` for the whole app. Because the same map
/// instance is reused everywhere, switching tabs never reloads tiles nor resets
/// the camera — it's configured once at startup.
@MainActor
final class MapHost {
    let mapView = MKMapView()
    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true

        mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true

        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 44.5, longitude: 8.5),
                span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 22)
            ),
            animated: false
        )

        for place in SpotPlace.sample {
            let a = SpotAnnotation(place: place)
            mapView.addAnnotation(a)
        }
    }
}

/// The persistent map as a SwiftUI view. Always returns the shared instance.
struct PersistentMapView: UIViewRepresentable {
    let host: MapHost

    func makeUIView(context: Context) -> MKMapView {
        host.configure()
        host.mapView.delegate = context.coordinator
        return host.mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let spot = annotation as? SpotAnnotation else { return nil }
            let id = "spot"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor(spot.place.rarity.primary)
            view.glyphImage = UIImage(systemName: "car.fill")
            view.displayPriority = .required
            return view
        }
    }
}

final class SpotAnnotation: NSObject, MKAnnotation {
    let place: SpotPlace
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }
    init(place: SpotPlace) { self.place = place }
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
