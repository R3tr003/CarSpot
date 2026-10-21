import SwiftUI

/// Posizioni di riposo del pannello (stile Apple Maps / Flighty).
enum SheetDetent: Int, CaseIterable, Sendable {
    case collapsed, medium, expanded

    var label: String {
        switch self {
        case .collapsed: "Chiuso"
        case .medium: "Medio"
        case .expanded: "Aperto"
        }
    }

    /// Un passo verso l'alto / verso il basso (accessibilità).
    var up: SheetDetent { SheetDetent(rawValue: min(rawValue + 1, 2)) ?? self }
    var down: SheetDetent { SheetDetent(rawValue: max(rawValue - 1, 0)) ?? self }

    /// Tap sulla maniglia: chiuso→medio→aperto→medio.
    var cycled: SheetDetent {
        switch self {
        case .collapsed: .medium
        case .medium: .expanded
        case .expanded: .medium
        }
    }
}

/// Ancora il contenuto di una schermata in una card scura trascinabile in basso,
/// con la mappa visibile e interattiva sopra (stile Flighty). Tre posizioni:
/// chiusa, media (default) e aperta a tutto schermo. La tab bar Liquid Glass
/// nativa fluttua sopra il fondo della card.
struct SheetCard<Content: View>: View {
    /// Frazione dell'altezza disponibile lasciata alla mappa in posizione media.
    var mapPeek: CGFloat = 0.30
    @ViewBuilder var content: Content

    @State private var detent: SheetDetent = .medium
    @State private var translation: CGFloat = 0
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Parte di card visibile da chiusa (maniglia + prima riga dell'header).
    private let collapsedVisible: CGFloat = 120
    /// Altezza della zona di trascinamento in cima alla card.
    private let dragZoneHeight: CGFloat = 56
    /// Larghezza riservata ai pulsanti dell'header (condividi + avatar) a destra.
    private let trailingControlsWidth: CGFloat = 140
    /// Extra di card sotto lo schermo per il rubber-band verso l'alto.
    private let overscrollSlack: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, safeTop: geo.safeAreaInsets.top,
                            safeBottom: geo.safeAreaInsets.bottom,
                            mapPeek: mapPeek, collapsedVisible: collapsedVisible)
            let top = currentTop(m, base: detent, translation: translation)

            card(m)
                .frame(height: m.height - m.expandedTop + overscrollSlack, alignment: .top)
                .offset(y: top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: detent)
        .onChange(of: isDragging) { _, dragging in
            // Gesto annullato dal sistema: torna alla posizione di riposo.
            if !dragging, translation != 0 { settle(to: detent, velocity: 0) }
        }
    }

    // MARK: - Card

    private func card(_ m: Metrics) -> some View {
        // Spazio che la card tiene sotto lo schermo nella posizione di riposo:
        // il contenuto scorre fino in fondo anche da medio/chiuso.
        let hidden = max(0, m.top(for: detent) - m.expandedTop + overscrollSlack)

        return VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .accessibilityHidden(true)
            content
                .safeAreaPadding(.bottom, hidden)
                .animation(nil, value: detent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(cardBackground.ignoresSafeArea(edges: .bottom))
        .clipShape(.rect(topLeadingRadius: CSRadius.lg, topTrailingRadius: CSRadius.lg))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: CSRadius.lg, topTrailingRadius: CSRadius.lg)
                .strokeBorder(
                    LinearGradient(colors: [CSColor.specular.opacity(0.45), .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { dragZone(m) }
        .shadow(color: .black.opacity(0.5), radius: 22, y: -6)
    }

    /// Zona di trascinamento: maniglia + header, tranne i pulsanti a destra.
    private func dragZone(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .overlay(alignment: .top) { handle }
                .gesture(dragGesture(m))
            Color.clear.frame(width: trailingControlsWidth)
        }
        .frame(height: dragZoneHeight)
    }

    private var handle: some View {
        Color.clear
            .frame(width: 88, height: 30)
            .contentShape(Rectangle())
            .onTapGesture { settle(to: detent.cycled, velocity: 0) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pannello")
            .accessibilityValue(detent.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: settle(to: detent.up, velocity: 0)
                case .decrement: settle(to: detent.down, velocity: 0)
                @unknown default: break
                }
            }
    }

    // MARK: - Gesto

    private func dragGesture(_ m: Metrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in translation = value.translation.height }
            .onEnded { value in
                let velocity = value.velocity.height
                let current = currentTop(m, base: detent, translation: value.translation.height)
                // Proiezione dell'inerzia (decelerazione tipo scroll view).
                let projected = current + (velocity / 1000) * 0.998 / (1 - 0.998)
                let target = SheetDetent.allCases.min {
                    abs(m.top(for: $0) - projected) < abs(m.top(for: $1) - projected)
                } ?? detent
                settle(to: target, velocity: velocity)
            }
    }

    /// Posizione y corrente: segue il dito 1:1 tra i limiti, con resistenza oltre.
    private func currentTop(_ m: Metrics, base: SheetDetent, translation: CGFloat) -> CGFloat {
        let raw = m.top(for: base) + translation
        if raw < m.expandedTop {
            return m.expandedTop - rubber(m.expandedTop - raw, in: m.height)
        }
        if raw > m.collapsedTop {
            return m.collapsedTop + rubber(raw - m.collapsedTop, in: m.height)
        }
        return raw
    }

    private func rubber(_ d: CGFloat, in h: CGFloat) -> CGFloat {
        (d * h * 0.55) / (h + 0.55 * abs(d))
    }

    private func settle(to target: SheetDetent, velocity: CGFloat) {
        let animation: Animation = if reduceMotion {
            .easeOut(duration: 0.2)
        } else {
            .spring(duration: 0.35, bounce: abs(velocity) > 800 ? 0.15 : 0)
        }
        withAnimation(animation) {
            detent = target
            translation = 0
        }
    }

    private var cardBackground: some View {
        ZStack {
            CSColor.base
            LinearGradient(colors: [CSColor.surface, CSColor.base],
                           startPoint: .top, endPoint: .bottom).opacity(0.6)
        }
    }

    // MARK: - Metriche

    /// Quote y (dall'alto dello schermo intero) delle tre posizioni.
    private struct Metrics {
        let height: CGFloat
        let expandedTop: CGFloat
        let mediumTop: CGFloat
        let collapsedTop: CGFloat

        init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat,
             mapPeek: CGFloat, collapsedVisible: CGFloat) {
            height = size.height
            expandedTop = safeTop
            mediumTop = safeTop + (size.height - safeTop) * mapPeek
            collapsedTop = max(mediumTop, size.height - safeBottom - collapsedVisible)
        }

        func top(for detent: SheetDetent) -> CGFloat {
            switch detent {
            case .collapsed: collapsedTop
            case .medium: mediumTop
            case .expanded: expandedTop
            }
        }
    }
}
