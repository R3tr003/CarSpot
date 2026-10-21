import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(SyncService.self) private var sync: SyncService?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
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
                            grid(shown)
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
    }

    private func grid(_ items: [StoredCard]) -> some View {
        LazyVGrid(columns: columns, spacing: CSSpace.md) {
            ForEach(items, id: \.id) { item in
                let card = item.asSpotCard
                NavigationLink {
                    CardDetailView(card: card)
                        .navigationTransition(.zoom(sourceID: card.id, in: cardNamespace))
                } label: {
                    SpotCardView(card: card, compact: true)
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
        GlassPanel {
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
        GlassPanel {
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
        HStack(spacing: CSSpace.md) {
            statTile(value: stored.count, label: "Carte", tint: CSColor.accent)
            statTile(value: stored.filter { $0.rarity == .leggendaria }.count,
                     label: "Leggendarie", tint: Rarity.leggendaria.primary)
            statTile(value: Set(stored.map { $0.make.lowercased() }).count,
                     label: "Marche", tint: Rarity.epica.primary)
        }
    }

    private func statTile(value: Int, label: LocalizedStringKey, tint: Color) -> some View {
        let text = value > 999 ? value.formatted(.number.notation(.compactName).locale(.app)) : "\(value)"
        return VStack(spacing: CSSpace.xxs) {
            Text(text)
                .font(CSFont.numeric(26)).foregroundStyle(CSColor.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label).eyebrow(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.md)
        .padding(.horizontal, CSSpace.xs)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
        .accessibilityElement(children: .combine)
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
                        Capsule().fill(.white.opacity(0.06))
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
