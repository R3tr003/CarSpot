import SwiftUI
import MapKit

/// Possiede l'UNICA `MKMapView` dell'app. La stessa istanza viene riusata ovunque:
/// cambiando tab la mappa non si ricarica e la camera non si resetta. Invece di
/// sta alla radice del guscio, sotto il pannello di sistema che contiene la `TabView`.
@MainActor
final class MapHost: NSObject, MKMapViewDelegate {
    let mapView = MKMapView()
    private var configured = false
    /// La camera segue l'utente una sola volta, alla prima posizione utile.
    private var followedUser = false

    /// Frazione di altezza lasciata alla mappa dal pannello in posizione media
    /// (`RootShellView.mediumDetent` = metà schermo). Il logo Maps/Legal resta invece
    /// fisso in fondo (margini di default), anche se il pannello lo copre.
    private let sheetPeek: CGFloat = 0.50
    /// Zoom "città" del primo centraggio.
    private let citySpan: CLLocationDegrees = 0.05
    /// Il cambio di regione in corso nasce da un gesto dell'utente (non da `setRegion`).
    private var userIsMoving = false
    /// Ultima interazione contata: al massimo una ogni 10 s per le statistiche.
    private var lastInteractionReport: ContinuousClock.Instant?
    private let interactionReportInterval: Duration = .seconds(10)

    func configure() {
        guard !configured else { return }
        configured = true

        mapView.delegate = self
        // Mostra il punto dell'utente: mai nei replay di sessione.
        AppServices.errors.maskInReplays(mapView)
        // Stile sobrio alla Flighty: mappa standard scura e attenuata, i marker
        // delle rarità restano l'unico colore forte.
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat,
                                                                    emphasisStyle: .muted)
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 44.5, longitude: 8.5),
                span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 22)
            ),
            animated: false
        )

        for place in SpotPlace.sample {
            mapView.addAnnotation(SpotAnnotation(place: place))
        }
    }

    /// Sposta la mappa nel container indicato (un solo genitore alla volta).
    /// Non tocca la regione: stessa istanza, stessa camera.
    func attach(to container: UIView) {
        configure()
        guard mapView.superview !== container else { return }
        mapView.removeFromSuperview()
        mapView.frame = container.bounds
        container.insertSubview(mapView, at: 0)
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard !followedUser, let location = userLocation.location,
              location.horizontalAccuracy >= 0 else { return }
        followedUser = true
        // Centro spostato a sud: l'utente cade a metà della fascia di mappa visibile
        // sopra il pannello (media), non dietro la card.
        let userY = sheetPeek / 2
        let center = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude - (0.5 - userY) * citySpan,
            longitude: location.coordinate.longitude)
        mapView.setRegion(
            MKCoordinateRegion(center: center,
                               span: MKCoordinateSpan(latitudeDelta: citySpan, longitudeDelta: citySpan)),
            animated: true)
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // Un gesto in corso lascia i recognizer interni della mappa in `began`/`ended`.
        userIsMoving = mapView.subviews.first?.gestureRecognizers?.contains {
            $0.state == .began || $0.state == .ended
        } ?? false
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard userIsMoving else { return }
        userIsMoving = false
        let now = ContinuousClock.now
        if let last = lastInteractionReport, now - last < interactionReportInterval { return }
        lastInteractionReport = now
        AppServices.errors.metric(count: "map.interaction")
    }

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

/// Container UIKit semplice: ospita la mappa condivisa quando la sua tab è attiva.
final class MapContainerView: UIView {
    let host: MapHost
    var isActive = false

    init(host: MapHost) {
        self.host = host
        super.init(frame: .zero)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isActive { host.attach(to: self) }
    }
}

/// Segnaposto della mappa dentro una tab: se `isActive` la mappa condivisa si
/// aggancia a questo container. Le altre tab restano vuote finché non diventano attive.
struct MapSlot: UIViewRepresentable {
    let host: MapHost
    let isActive: Bool

    func makeUIView(context: Context) -> MapContainerView {
        let container = MapContainerView(host: host)
        container.isActive = isActive
        if isActive { host.attach(to: container) }
        return container
    }

    func updateUIView(_ container: MapContainerView, context: Context) {
        container.isActive = isActive
        if isActive { host.attach(to: container) }
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
        SpotPlace(name: String(localized: "Firenze"), latitude: 43.77, longitude: 11.25, rarity: .leggendaria),
        SpotPlace(name: String(localized: "Roma"), latitude: 41.90, longitude: 12.49, rarity: .epica),
        SpotPlace(name: String(localized: "Milano"), latitude: 45.46, longitude: 9.19, rarity: .rara)
    ]
}
