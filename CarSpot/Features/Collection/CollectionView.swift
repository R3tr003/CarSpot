import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(SyncService.self) private var sync: SyncService?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Le ripetizioni (stessa auto già catturata) restano in cronologia, non in collezione.
    @Query(filter: #Predicate<StoredCard> { $0.isRepeat == false },
           sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @State private var filter: Rarity? = nil
    @Namespace private var cardNamespace

    private let columns = [GridItem(.flexible(), spacing: CSSpace.md),
                           GridItem(.flexible(), spacing: CSSpace.md)]

    /// Carte filtrate per rarità. Resta sui modelli: la conversione in `SpotCard`
    /// (che legge la foto) avviene solo per le celle realmente create dalla griglia lazy.
    private var visible: [StoredCard] {
        guard let filter else { return stored }
        return stored.filter { $0.rarity == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CSSpace.lg) {
                    SheetHeader(title: "Collezione")
                    if stored.isEmpty {
                        emptyState
                    } else {
                        statsHeader
                        filterRow
                        let shown = visible
                        if shown.isEmpty, let filter {
                            noResults(for: filter)
                        } else {
                            grid(shown, copies: copyCounts)
                        }
                    }
                }
                .padding(CSSpace.lg)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            // Sfondo trasparente: sopra la card si deve vedere la mappa.
            .containerBackground(.clear, for: .navigation)
            .scrollContentBackground(.hidden)
        }
        // Filtro per rarità: nome del case ("comune"…) o "all", indipendente dalla lingua.
        .onChange(of: filter) { _, new in
            AppServices.analytics.track(.collectionFiltered(filter: new.map { String(describing: $0) } ?? "all"))
        }
    }

    /// Copie per modello, calcolate una volta per render (non per cella).
    private var copyCounts: [String: Int] {
        stored.reduce(into: [:]) { $0[CardCopies.key(make: $1.make, model: $1.model), default: 0] += 1 }
    }

    private func grid(_ items: [StoredCard], copies: [String: Int]) -> some View {
        LazyVGrid(columns: columns, spacing: CSSpace.md) {
            ForEach(items, id: \.id) { item in
                let card = item.asSpotCard
                NavigationLink {
                    CardDetailView(card: card)
                        .navigationTransition(.zoom(sourceID: card.id, in: cardNamespace))
                } label: {
                    SpotCardView(card: card, compact: true,
                                 copies: copies[CardCopies.key(make: item.make, model: item.model)] ?? 1)
                        .matchedTransitionSource(id: card.id, in: cardNamespace)
                        // Foto ripristinata dal cloud: si scarica solo quando la carta appare.
                        .task(id: card.id) { await sync?.loadPhotoIfNeeded(cardId: card.id) }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0), value: filter)
    }

    // MARK: - Stati vuoti

    private var emptyState: some View {
        Surface(.hero) {
            VStack(spacing: CSSpace.md) {
                Image(systemName: "camera.viewfinder")
                    .font(CSFont.display(34))
                    .foregroundStyle(CSColor.accent)
                    .accessibilityHidden(true)
                Text("Nessuna carta ancora")
                    .font(CSFont.title(20)).foregroundStyle(CSColor.ink)
                Text("Tocca la fotocamera in basso a destra per catturare la tua prima auto.")
                    .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func noResults(for rarity: Rarity) -> some View {
        Surface(.group) {
            VStack(spacing: CSSpace.md) {
                Text("Nessuna carta \(rarity.localizedName)")
                    .font(CSFont.title(20)).foregroundStyle(CSColor.ink)
                GhostButton(title: "Mostra tutte") { filter = nil }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Statistiche e filtri

    private var statsHeader: some View {
        // Contatori sui modelli: niente conversione in SpotCard (non tocca le foto).
        KPIStrip([
            .init("Carte", value: compact(stored.count)),
            .init("Leggendarie", value: compact(stored.filter { $0.rarity == .leggendaria }.count)),
            .init("Marche", value: compact(Set(stored.map { $0.make.lowercased() }).count))
        ])
    }

    private func compact(_ value: Int) -> String {
        value > 999 ? value.formatted(.number.notation(.compactName).locale(.app)) : "\(value)"
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CSSpace.sm) {
                FilterChip(title: "Tutte", tint: CSColor.accent,
                           selected: filter == nil) { filter = nil }
                ForEach(Rarity.allCases) { rarity in
                    FilterChip(title: rarity.displayName, tint: rarity.primary,
                               selected: filter == rarity) {
                        filter = (filter == rarity) ? nil : rarity
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct FilterChip: View {
    let title: LocalizedStringResource
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CSFont.caption(13))
                .foregroundStyle(selected ? CSColor.inkInverse : CSColor.inkSecondary)
                .padding(.horizontal, CSSpace.md)
                .frame(minHeight: CSSize.minTap)
                .background {
                    if selected {
                        Capsule().fill(tint)
                    } else {
                        Capsule().fill(CSColor.nested)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(CSPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview { CollectionView().preferredColorScheme(.dark) }
