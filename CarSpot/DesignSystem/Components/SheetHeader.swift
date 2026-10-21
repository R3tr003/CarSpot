import SwiftUI

/// Header used at the top of each sheet screen: big title on the left, an optional
/// share button and the user avatar on the right (Flighty-style banner).
/// L'avatar apre un menu nativo (vetro di sistema): profilo e impostazioni, via le
/// azioni d'ambiente `openProfile` / `openSettings`.
struct SheetHeader: View {
    let title: LocalizedStringKey
    /// Il bottone Condividi compare solo se l'azione è fornita.
    var onShare: (() -> Void)? = nil

    @Environment(\.openProfile) private var openProfile
    @Environment(\.openSettings) private var openSettings
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
            Menu {
                // Titolo + sottotitolo come in Flighty ("Andrea / Modifica profilo").
                Button(action: openProfile) {
                    Text(menuName)
                    Text("Modifica profilo")
                    Image(systemName: "person.crop.circle.fill")
                }
                Button(action: openSettings) {
                    Label("Impostazioni", systemImage: "gearshape")
                }
            } label: {
                UserAvatar(size: 50, name: account?.username ?? "", avatar: account?.avatar)
                    .frame(minWidth: CSSize.minTap, minHeight: CSSize.minTap)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Profilo")
            .accessibilityHint("Apre profilo e impostazioni")
        }
    }

    /// Nome e cognome se ci sono, altrimenti il nome da spotter.
    private var menuName: String {
        if let full = AppServices.auth.personName?.fullName, !full.isEmpty { return full }
        if let name = account?.username, !name.isEmpty { return "@\(name)" }
        return String(localized: "Spotter")
    }
}

/// Environment action to present the profile (triggered by the header avatar).
extension EnvironmentValues {
    @Entry var openProfile: () -> Void = {}
    @Entry var openSettings: () -> Void = {}
}

/// Avatar circolare: la foto profilo se c'è (`avatar`), altrimenti l'iniziale del nome su
/// accent pieno, senza alone (i colori di rarità sono riservati alle carte); senza nome
/// mostra un glifo persona.
struct UserAvatar: View {
    var size: CGFloat = 44
    var name: String = ""
    var avatar: AvatarRef? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?

    private var initial: String? {
        name.first.map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            Circle().fill(CSColor.accent)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            } else if let initial {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(CSColor.inkInverse)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(CSColor.inkInverse)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: image == nil)
        .task(id: avatar) {
            guard let avatar else {
                image = nil
                return
            }
            image = await AvatarCache.shared.image(for: avatar)
        }
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
