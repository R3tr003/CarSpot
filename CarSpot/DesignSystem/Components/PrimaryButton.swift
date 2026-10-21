import SwiftUI

/// Feedback di pressione condiviso: leggero rimpicciolimento a molla, senza rimbalzo.
/// Con Reduce Motion solo un'attenuazione. Usarlo per ogni pulsante custom.
struct CSPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

/// Azione principale: capsula a colore pieno (il primo di `gradient`), senza
/// gradiente né alone, con la molla di pressione condivisa.
struct PrimaryButton: View {
    var title: LocalizedStringKey
    var icon: String? = nil
    var gradient: [Color] = [CSColor.accent]
    /// `false` quando l'azione produce già il suo haptic (es. salvataggio con `.success`).
    var haptic: Bool = true
    var action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: CSSpace.xs) {
                if let icon { Image(systemName: icon).font(CSFont.title(17)) }
                Text(title).font(CSFont.title(17))
            }
            .foregroundStyle(CSColor.inkInverse)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, CSSpace.md)
            .background(Capsule().fill(gradient.first ?? CSColor.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(CSPressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: taps) { _, _ in haptic }
    }
}

/// Subtle glass secondary action.
struct GhostButton: View {
    var title: LocalizedStringKey
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CSSpace.xs) {
                if let icon { Image(systemName: icon).font(CSFont.body(16)) }
                Text(title).font(CSFont.body(16))
            }
            .foregroundStyle(CSColor.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, CSSpace.md)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(CSPressStyle())
    }
}
