import SwiftUI

/// Marchio di CarSpot (lo stesso glifo dell'icona: tetto + scia a C, ruota ambra), vettoriale
/// da `Assets.xcassets`. Solo nei momenti di identità dell'app (login, intro): niente aloni,
/// è decorativo per VoiceOver. Sorgente in `design/icon/build_icon_layers.py`.
struct BrandMark: View {
    /// Larghezza in punti, scalata con Dynamic Type.
    @ScaledMetric private var width: CGFloat

    init(width: CGFloat) {
        _width = ScaledMetric(wrappedValue: width, relativeTo: .largeTitle)
    }

    var body: some View {
        Image(.brandMark)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: CSSpace.xl) {
        BrandMark(width: 104)
        BrandMark(width: 200)
    }
    .padding()
    .background(CSColor.base)
}
