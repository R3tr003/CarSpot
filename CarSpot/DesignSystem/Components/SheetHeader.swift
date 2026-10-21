import SwiftUI

/// Header used at the top of each sheet screen: big title on the left, an optional
/// share button and the tappable user avatar on the right (Flighty-style banner).
/// Tapping the avatar opens the profile via the `openProfile` environment action.
struct SheetHeader: View {
    let title: String
    /// Il bottone Condividi compare solo se l'azione è fornita.
    var onShare: (() -> Void)? = nil

    @Environment(\.openProfile) private var openProfile
    @Environment(ProfileAccount.self) private var account: ProfileAccount?

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(CSFont.display(34))
                .foregroundStyle(CSColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(CSFont.title(17))
                        .foregroundStyle(CSColor.ink)
                        .frame(width: CSSize.minTap, height: CSSize.minTap)
                        .glassEffect(.regular, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(CSPressStyle())
                .accessibilityLabel("Condividi")
            }
            Button(action: openProfile) {
                UserAvatar(size: 50, name: account?.username ?? "")
                    .frame(minWidth: CSSize.minTap, minHeight: CSSize.minTap)
                    .contentShape(.circle)
            }
            .buttonStyle(CSPressStyle())
            .accessibilityLabel("Profilo")
            .accessibilityHint("Apre il tuo profilo")
        }
    }
}

/// Environment action to present the profile (triggered by the header avatar).
extension EnvironmentValues {
    @Entry var openProfile: () -> Void = {}
}

/// Circular user avatar: iniziale del nome su gradiente accent (i colori di rarità
/// sono riservati alle carte); senza nome mostra un glifo persona.
struct UserAvatar: View {
    var size: CGFloat = 44
    var name: String = ""

    private var initial: String? {
        name.first.map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            Circle().fill(CSColor.accentGradient)
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            if let initial {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(CSColor.inkInverse)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(CSColor.inkInverse)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: CSColor.accent.opacity(0.3), radius: 8)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        AsphaltBackground()
        VStack {
            SheetHeader(title: "Collezione")
            SheetHeader(title: "Oggi", onShare: {})
            UserAvatar(size: 88, name: "andre")
        }.padding()
    }
}
