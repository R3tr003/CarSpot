import SwiftUI

/// Primary call-to-action with a gradient fill, specular edge and press spring.
struct PrimaryButton: View {
    var title: String
    var icon: String? = nil
    var gradient: [Color] = Rarity.rara.gradient
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(CSFont.title(17))
            }
            .foregroundStyle(.black.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1).blendMode(.overlay)
            )
            .shadow(color: gradient.first!.opacity(0.5), radius: 18, y: 8)
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.spring(response: 0.2)) { pressed = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.3)) { pressed = false } }
        )
    }
}

/// Subtle glass secondary action.
struct GhostButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(CSFont.body(16))
            }
            .foregroundStyle(CSColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
