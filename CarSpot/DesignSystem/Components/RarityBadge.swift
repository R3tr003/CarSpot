import SwiftUI

/// Nome di una rarità con il suo colore unico: pallino + testo, nessun gradiente.
/// `compact` = senza capsula (legenda in linea, per la carta).
struct RarityBadge: View {
    let rarity: Rarity
    var compact: Bool = false

    var body: some View {
        HStack(spacing: CSSpace.xs) {
            Circle()
                .fill(rarity.color)
                .frame(width: 7, height: 7)
            Text(rarity.displayName)
                .font(CSFont.micro)
                .fontWeight(.semibold)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(compact ? CSColor.inkSecondary : CSColor.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 0 : 10)
        .padding(.vertical, compact ? 0 : 6)
        .background {
            if !compact { Capsule().fill(CSColor.nested) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rarità \(rarity.localizedName)")
    }
}

#Preview {
    ZStack {
        CSColor.panel
        VStack(spacing: 12) {
            ForEach(Rarity.allCases) { RarityBadge(rarity: $0) }
            RarityBadge(rarity: .rara, compact: true)
        }
    }
}
