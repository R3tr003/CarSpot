import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(SyncService.self) private var sync: SyncService?
    @Query(sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @State private var filter: Rarity? = nil
    @Namespace private var cardNamespace

    private let columns = [GridItem(.flexible(), spacing: CSSpace.md),
                           GridItem(.flexible(), spacing: CSSpace.md)]

    private var cards: [SpotCard] { stored.map(\.asSpotCard) }

    private var visible: [SpotCard] {
        guard let filter else { return cards }
        return cards.filter { $0.rarity == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CSSpace.lg) {
                    SheetHeader(title: "Collezione")
                    statsHeader
                    filterRow
                    LazyVGrid(columns: columns, spacing: CSSpace.md) {
                        ForEach(visible) { card in
                            NavigationLink {
                                CardDetailView(card: card)
                                    .navigationTransition(.zoom(sourceID: card.id, in: cardNamespace))
                            } label: {
                                SpotCardView(card: card)
                                    .matchedTransitionSource(id: card.id, in: cardNamespace)
                                    // Foto ripristinata dal cloud: si scarica solo quando la carta appare.
                                    .task(id: card.id) { await sync?.loadPhotoIfNeeded(cardId: card.id) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(CSSpace.lg)
                .padding(.bottom, 130)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: filter)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            // Sfondo trasparente: sopra la card si deve vedere la mappa.
            .containerBackground(.clear, for: .navigation)
            .scrollContentBackground(.hidden)
        }
    }

    private var statsHeader: some View {
        HStack(spacing: CSSpace.md) {
            statTile(value: "\(cards.count)", label: "Carte", tint: CSColor.accent)
            statTile(value: "\(cards.filter { $0.rarity == .leggendaria }.count)",
                     label: "Leggendarie", tint: Rarity.leggendaria.primary)
            statTile(value: "18", label: "Marche", tint: Rarity.epica.primary)
        }
    }

    private func statTile(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(CSFont.numeric(26)).foregroundStyle(CSColor.ink)
            Text(label).eyebrow(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CSSpace.sm) {
                FilterChip(title: "Tutte", tint: CSColor.accent,
                           selected: filter == nil) { filter = nil }
                ForEach(Rarity.allCases) { rarity in
                    FilterChip(title: rarity.rawValue, tint: rarity.primary,
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
    let title: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CSFont.caption(13))
                .foregroundStyle(selected ? .black.opacity(0.85) : CSColor.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background {
                    if selected {
                        Capsule().fill(tint)
                    } else {
                        Capsule().fill(.white.opacity(0.06))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview { CollectionView().preferredColorScheme(.dark) }
