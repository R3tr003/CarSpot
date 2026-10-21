import SwiftUI

/// Pill that names a rarity with its symbol and gradient.
struct RarityBadge: View {
    let rarity: Rarity
    var compact: Bool = false

    var body: some View {
        HStack(spacing: CSSpace.xs) {
            Image(systemName: rarity.symbol)
                .font(.system(.caption2, design: .rounded, weight: .heavy))
                .imageScale(compact ? .medium : .small)
            if !compact {
                Text(rarity.displayName)
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(CSColor.inkInverse)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(
            Capsule().fill(rarity.linearGradient)
        )
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: rarity.primary.opacity(rarity.glowStrength), radius: 8, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rarità \(rarity.localizedName)")
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        VStack(spacing: 12) {
            ForEach(Rarity.allCases) { RarityBadge(rarity: $0) }
            RarityBadge(rarity: .rara, compact: true)
        }
    }
}
