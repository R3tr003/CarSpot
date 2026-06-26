import SwiftUI

/// Header used at the top of each sheet screen: big title on the left, a share
/// button and the user avatar on the right (Flighty-style banner).
struct SheetHeader: View {
    let title: String
    var onShare: () -> Void = {}

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(CSFont.display(34))
                .foregroundStyle(CSColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            UserAvatar(size: 50)
        }
    }
}

/// Circular user avatar. Placeholder gradient with an initial until a real
/// profile photo is wired in.
struct UserAvatar: View {
    var size: CGFloat = 44
    var initial: String = "A"

    var body: some View {
        ZStack {
            Circle().fill(Rarity.leggendaria.linearGradient)
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(.black.opacity(0.8))
        }
        .frame(width: size, height: size)
        .shadow(color: Rarity.leggendaria.primary.opacity(0.4), radius: 8)
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        SheetHeader(title: "Collezione").padding()
    }
}
