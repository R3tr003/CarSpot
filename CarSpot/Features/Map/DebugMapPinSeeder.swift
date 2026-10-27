#if DEBUG
import SwiftUI
import SwiftData
import CoreLocation

/// SOLO DEBUG, SOLO SU RICHIESTA: con `-seedMapPins YES` dà alle carte senza coordinate
/// (quelle fatte prima della mappa) la posizione attuale dell'utente, sparpagliate entro
/// ~1,5 km così i segnaposto sono distinti e si vede il raggruppamento. Serve per provare
/// la mappa senza ri-scattare. Le carte toccate si segnano in UserDefaults:
/// `-clearMapPins YES` toglie le coordinate SOLO a quelle, mai a quelle vere degli scatti.
/// Le coordinate restano locali come sempre.
struct DebugMapPinSeeder: View {
    @Environment(\.modelContext) private var context

    private static let seededKey = "debug.seededMapPinIDs"
    private static let spreadMeters = 1_500.0

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .task { await run() }
    }

    private func run() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "clearMapPins") {
            clear()
        } else if defaults.bool(forKey: "seedMapPins") {
            await seed()
        }
    }

    private var seededIDs: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: Self.seededKey) ?? []).compactMap(UUID.init)) }
        nonmutating set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: Self.seededKey) }
    }

    private func clear() {
        let marked = seededIDs
        guard !marked.isEmpty else { return }
        let cards = (try? context.fetch(FetchDescriptor<StoredCard>(
            predicate: #Predicate { marked.contains($0.id) }))) ?? []
        for card in cards { card.latitude = nil; card.longitude = nil }
        try? context.save()
        seededIDs = []
    }

    private func seed() async {
        // Serve il permesso già concesso: altrimenti nessun effetto.
        guard let location = await OneShotLocationSource().currentLocation() else { return }
        let missing = (try? context.fetch(FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.latitude == nil && !$0.isRepeat }))) ?? []
        guard !missing.isEmpty else { return }
        for card in missing {
            let spot = Self.scattered(from: location.coordinate, seed: card.id)
            card.latitude = spot.latitude
            card.longitude = spot.longitude
        }
        try? context.save()
        seededIDs = seededIDs.union(missing.map(\.id))
    }

    /// Punto a distanza e direzione fisse per ogni carta (stesso id → stesso posto).
    private static func scattered(from base: CLLocationCoordinate2D, seed: UUID) -> (latitude: Double, longitude: Double) {
        let bytes = seed.uuid
        let angle = Double(bytes.0) / 255 * 2 * .pi
        let distance = (0.15 + 0.85 * Double(bytes.1) / 255) * spreadMeters
        let metersPerDegree = 111_320.0
        let dLat = distance * cos(angle) / metersPerDegree
        let dLon = distance * sin(angle) / (metersPerDegree * max(cos(base.latitude * .pi / 180), 0.01))
        return (base.latitude + dLat, base.longitude + dLon)
    }
}
#endif
