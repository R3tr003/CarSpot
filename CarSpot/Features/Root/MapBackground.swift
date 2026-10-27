import SwiftUI
import MapKit

/// Possiede l'UNICA `MKMapView` dell'app. La stessa istanza viene riusata ovunque:
/// cambiando tab la mappa non si ricarica e la camera non si resetta. Sta alla radice
/// del guscio, sotto il pannello di sistema che contiene la `TabView`.
///
/// Mostra le catture reali dell'utente (`SpotPin`, alimentate da `MapPinsFeed`) e dice
/// al guscio quali carte sono state toccate con `onSelectionChange`.
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
    /// Lato minimo (in metri) dell'inquadratura del primo centraggio: zoom "quartiere/città".
    private let minFrameMeters: CLLocationDistance = 6_000
    /// Le catture più lontane di così dall'utente non entrano nell'inquadratura iniziale
    /// (una gita a 300 km non deve zoomare via la città in cui sei).
    private let framingRadius: CLLocationDistance = 60_000
    /// Raggruppamento dei segnaposto vicini.
    private static let clusterID = "spot"
    /// Il cambio di regione in corso nasce da un gesto dell'utente (non da `setRegion`).
    private var userIsMoving = false
    /// Ultima interazione contata: al massimo una ogni 10 s per le statistiche.
    private var lastInteractionReport: ContinuousClock.Instant?
    private let interactionReportInterval: Duration = .seconds(10)

    /// Carte toccate sulla mappa (vuoto = nessuna selezione). Chiamata sul main actor.
    var onSelectionChange: (@MainActor ([UUID]) -> Void)?
    private var pins: [SpotPin] = []
    private var annotations: [UUID: SpotAnnotation] = [:]
    /// L'inquadratura iniziale è già stata decisa (con la posizione dell'utente o, senza, sulle catture).
    private var framed = false
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

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
    }

    // MARK: Segnaposto

    /// Allinea la mappa all'elenco di catture: aggiunge, toglie o sostituisce solo i
    /// segnaposto cambiati. La `MKMapView` non viene ricreata né la camera spostata
    /// (salvo la prima inquadratura quando manca la posizione dell'utente).
    func apply(pins newPins: [SpotPin]) {
        pins = newPins
        let incoming = Dictionary(newPins.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        let stale = annotations.filter { incoming[$0.key] != $0.value.pin }
        if !stale.isEmpty {
            mapView.removeAnnotations(Array(stale.values))
            for key in stale.keys { annotations[key] = nil }
        }
        let fresh = incoming.values
            .filter { annotations[$0.id] == nil }
            .map { SpotAnnotation(pin: $0) }
        for annotation in fresh { annotations[annotation.pin.id] = annotation }
        mapView.addAnnotations(fresh)

        // Senza posizione dell'utente (permesso negato) la mappa resterebbe sull'Europa:
        // si inquadrano le catture. Con la posizione ci pensa il primo fix.
        if !framed, !newPins.isEmpty, Self.locationIsUnavailable {
            framed = true
            frameCamera(around: nil)
        }
    }

    /// Toglie la selezione (chiusura del pannello del segnaposto).
    func deselectAll() {
        for annotation in mapView.selectedAnnotations { mapView.deselectAnnotation(annotation, animated: !reduceMotion) }
    }

    private static var locationIsUnavailable: Bool {
        switch CLLocationManager().authorizationStatus {
        case .denied, .restricted: true
        default: false
        }
    }

    // MARK: Inquadratura

    /// Quadrato di `meters` di lato centrato su una coordinata.
    private static func square(around coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) -> MKMapRect {
        let center = MKMapPoint(coordinate)
        let side = meters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        return MKMapRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Inquadra l'utente (se c'è) e le sue catture vicine; senza utente, tutte le catture.
    /// Il fondo è lasciato libero per il pannello in posizione media, così l'utente
    /// cade a metà della fascia di mappa visibile e non dietro la card.
    private func frameCamera(around user: CLLocation?) {
        var rect = MKMapRect.null
        if let user {
            rect = Self.square(around: user.coordinate, meters: minFrameMeters)
            for pin in pins {
                let distance = CLLocation(latitude: pin.latitude, longitude: pin.longitude).distance(from: user)
                guard distance <= framingRadius else { continue }
                rect = rect.union(Self.square(around: pin.coordinate, meters: minFrameMeters / 2))
            }
        } else {
            for pin in pins {
                rect = rect.union(Self.square(around: pin.coordinate, meters: minFrameMeters / 2))
            }
        }
        guard !rect.isNull else { return }
        let insets = UIEdgeInsets(top: mapView.safeAreaInsets.top + CSSpace.xl,
                                  left: CSSpace.lg + CSSpace.xs,
                                  bottom: mapView.bounds.height * sheetPeek + CSSpace.lg,
                                  right: CSSpace.lg + CSSpace.xs)
        mapView.setVisibleMapRect(rect, edgePadding: insets, animated: !reduceMotion)
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
        framed = true
        frameCamera(around: location)
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
        if let cluster = annotation as? MKClusterAnnotation {
            return clusterView(for: cluster, in: mapView)
        }
        guard let spot = annotation as? SpotAnnotation else { return nil }
        let id = "spot"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.clusteringIdentifier = Self.clusterID
        view.markerTintColor = UIColor(spot.pin.rarity.color)
        view.glyphTintColor = UIColor(CSColor.inkInverse)
        view.glyphImage = UIImage(systemName: "car.fill")
        view.displayPriority = .required
        view.canShowCallout = false
        view.titleVisibility = .hidden
        view.subtitleVisibility = .hidden
        view.animatesWhenAdded = !reduceMotion
        view.isAccessibilityElement = true
        view.accessibilityLabel = spot.pin.accessibilityLabel
        view.accessibilityHint = String(localized: "Apre la carta")
        view.accessibilityTraits = .button
        return view
    }

    /// Gruppo di segnaposto vicini: numero di carte, colore della rarità solo se è la stessa
    /// per tutte (con rarità miste un colore direbbe una cosa falsa: neutro).
    private func clusterView(for cluster: MKClusterAnnotation, in mapView: MKMapView) -> MKAnnotationView {
        let id = "spotCluster"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: id)
        view.annotation = cluster
        let members = cluster.memberAnnotations.compactMap { $0 as? SpotAnnotation }
        let rarities = Set(members.map(\.pin.rarity))
        let tint = rarities.count == 1 ? rarities.first!.color : CSColor.inkSecondary
        view.markerTintColor = UIColor(tint)
        view.glyphTintColor = UIColor(CSColor.inkInverse)
        view.glyphText = "\(members.count)"
        view.displayPriority = .defaultHigh
        view.canShowCallout = false
        view.titleVisibility = .hidden
        view.subtitleVisibility = .hidden
        view.animatesWhenAdded = !reduceMotion
        view.isAccessibilityElement = true
        view.accessibilityLabel = String(localized: "Gruppo di \(members.count) carte")
        view.accessibilityHint = String(localized: "Apre l'elenco delle carte")
        view.accessibilityTraits = .button
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        let ids: [UUID]
        switch view.annotation {
        case let spot as SpotAnnotation:
            ids = [spot.pin.id]
        case let cluster as MKClusterAnnotation:
            ids = cluster.memberAnnotations.compactMap { ($0 as? SpotAnnotation)?.pin.id }
        default:
            return
        }
        guard !ids.isEmpty else { return }
        onSelectionChange?(ids)
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        // Passando da un segnaposto a un altro MapKit deseleziona e poi seleziona: si
        // guarda lo stato un attimo dopo, e si chiude solo se non c'è più nulla di selezionato.
        Task { @MainActor [weak self] in
            guard let self, self.mapView.selectedAnnotations.isEmpty else { return }
            self.onSelectionChange?([])
        }
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
