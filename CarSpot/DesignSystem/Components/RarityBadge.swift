import SwiftUI

/// Pill that names a rarity with its symbol and gradient.
struct RarityBadge: View {
    let rarity: Rarity
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: rarity.symbol)
                .font(.system(size: compact ? 9 : 11, weight: .black))
            if !compact {
                Text(rarity.rawValue)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(
            Capsule().fill(rarity.linearGradient)
        )
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: rarity.primary.opacity(rarity.glowStrength), radius: 8, y: 2)
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        VStack(spacing: 12) {
            ForEach(Rarity.allCases) { RarityBadge(rarity: $0) }
        }
    }
}
