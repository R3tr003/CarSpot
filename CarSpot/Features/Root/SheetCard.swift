import SwiftUI

/// Anchors a screen's content in a rounded dark card at the bottom of the screen,
/// leaving the map visible above it (Flighty-style). The native Liquid Glass tab
/// bar floats over the bottom of this card.
struct SheetCard<Content: View>: View {
    /// Fraction of the height left for the map at the top.
    var mapPeek: CGFloat = 0.30
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: geo.size.height * mapPeek)
                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(cardBackground)
                .clipShape(.rect(topLeadingRadius: CSRadius.lg, topTrailingRadius: CSRadius.lg))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: CSRadius.lg, topTrailingRadius: CSRadius.lg)
                        .strokeBorder(
                            LinearGradient(colors: [CSColor.specular.opacity(0.45), .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.5), radius: 22, y: -6)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var cardBackground: some View {
        ZStack {
            CSColor.base
            LinearGradient(colors: [CSColor.surface, CSColor.base],
                           startPoint: .top, endPoint: .bottom).opacity(0.6)
        }
    }
}
