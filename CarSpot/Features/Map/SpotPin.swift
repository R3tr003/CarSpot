import SwiftUI
import SwiftData
import MapKit

/// Un segnaposto della mappa: una carta con la posizione esatta dello scatto.
/// Esiste solo in memoria: le coordinate non vanno mai in cloud, analytics o log.
struct SpotPin: Identifiable, Equatable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let rarity: Rarity
    /// "Marca Modello" per VoiceOver.
    let title: String
    let area: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Una frase sola: "Ferrari 488, rarità Epica, Vanchiglia".
    var accessibilityLabel: String {
        let rarityText = String(localized: "rarità \(rarity.localizedName)")
        return [title, rarityText, area].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Segnaposto sulla `MKMapView`.
final class SpotAnnotation: NSObject, MKAnnotation {
    let pin: SpotPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    init(pin: SpotPin) { self.pin = pin }
}

/// Tiene allineati i segnaposti della mappa alle carte in SwiftData, senza ricreare la
/// `MKMapView`: la view è invisibile, osserva `@Query` e a ogni cambio (salvataggio,
/// cancellazione, rarità) passa all'host solo l'elenco aggiornato.
///
/// Le ripetizioni (`isRepeat`, stessa auto) restano fuori: stesso posto della prima
/// cattura, 0 punti e già escluse da Collezione e obiettivi. Sulla mappa farebbero solo
/// rumore e gonfierebbero i raggruppamenti.
struct MapPinsFeed: View {
    let host: MapHost

    @Query private var cards: [StoredCard]

    init(host: MapHost) {
        self.host = host
        var descriptor = FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.latitude != nil && $0.longitude != nil && !$0.isRepeat })
        // La foto (file esterno) non serve alla mappa: non si carica.
        descriptor.propertiesToFetch = [
            \.id, \.make, \.model, \.rarityRaw, \.spottedArea, \.latitude, \.longitude, \.isRepeat,
        ]
        _cards = Query(descriptor)
    }

    private var pins: [SpotPin] {
        cards.compactMap { card in
            guard let spot = card.spotCoordinate else { return nil }
            return SpotPin(id: card.id, latitude: spot.latitude, longitude: spot.longitude,
                           rarity: card.rarity, title: "\(card.make) \(card.model)",
                           area: card.spottedArea)
        }
    }

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: pins, initial: true) { _, new in
                host.apply(pins: new)
            }
    }
}
