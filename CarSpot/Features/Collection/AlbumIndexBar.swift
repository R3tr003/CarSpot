import SwiftUI

/// Indice A–Z sul bordo destro: tocco o trascinamento saltano alla marca con quella iniziale.
/// Nascosto con meno di `minimumSections` sezioni (non serve per saltare).
struct AlbumIndexBar: View {
    struct Entry: Identifiable, Equatable {
        let letter: String
        /// Id della prima sezione con questa iniziale.
        let sectionID: String
        var id: String { letter }
    }

    static let minimumSections = 6

    let entries: [Entry]
    let onSelect: (String) -> Void

    /// Il genitore limita il Dynamic Type, così questa misura vede il tetto.
    @ScaledMetric(relativeTo: .caption2) private var letterHeight: CGFloat = 14
    /// Area tattile della colonna.
    private static let touchWidth: CGFloat = 30

    @State private var current = 0
    @State private var lastSent: String?
    /// Cambia solo quando si salta a una nuova lettera: è il trigger dell'haptic.
    @State private var feedback = 0

    /// Iniziali delle sezioni, in ordine; il resto (es. "Fuori catalogo") non entra.
    static func entries(for sections: [AlbumSection]) -> [Entry] {
        var seen = Set<String>()
        var result: [Entry] = []
        for section in sections where section.id != AlbumBuilder.uncatalogedID {
            let folded = section.title.folding(options: .diacriticInsensitive, locale: nil)
            guard let first = folded.first else { continue }
            let letter = first.isLetter ? String(first).uppercased() : "#"
            if seen.insert(letter).inserted { result.append(Entry(letter: letter, sectionID: section.id)) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                Text(entry.letter)
                    .font(CSFont.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(CSColor.accent)
                    .frame(width: Self.touchWidth, height: letterHeight)
            }
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let i = min(max(Int(value.location.y / letterHeight), 0), entries.count - 1)
                    select(i)
                }
                .onEnded { _ in lastSent = nil }
        )
        .sensoryFeedback(.selection, trigger: feedback)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Indice alfabetico")
        .accessibilityValue(entries.indices.contains(current) ? entries[current].letter : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(min(current + 1, entries.count - 1))
            case .decrement: select(max(current - 1, 0))
            @unknown default: break
            }
        }
    }

    private func select(_ i: Int) {
        guard entries.indices.contains(i) else { return }
        current = i
        guard lastSent != entries[i].letter else { return }
        lastSent = entries[i].letter
        feedback += 1
        onSelect(entries[i].sectionID)
    }
}
