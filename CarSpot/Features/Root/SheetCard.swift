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

/// Ancora il contenuto di una schermata in una card scura trascinabile, con la
/// mappa visibile e interattiva sopra (stile Flighty). Da chiusa e media la card
/// è flottante: staccata dai bordi, angoli concentrici a quelli del display e la
/// tab bar Liquid Glass nativa che ci sta dentro, in fondo. Salendo verso
/// "aperta" si allarga a tutta larghezza e si ferma sotto la Dynamic Island.
struct SheetCard<Content: View>: View {
    /// Frazione dell'altezza disponibile lasciata alla mappa in posizione media.
    var mapPeek: CGFloat = 0.30
    @ViewBuilder var content: Content

    @State private var detent: SheetDetent = .medium
    @State private var translation: CGFloat = 0
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distacco della card dai bordi (lati e fondo) da chiusa/media.
    private let floatingInset: CGFloat = 12
    /// Altezza della zona di trascinamento in cima alla card (maniglia + header).
    private let dragZoneHeight: CGFloat = 80
    /// Larghezza riservata ai pulsanti dell'header (condividi + avatar) a destra.
    private let trailingControlsWidth: CGFloat = 140

    var body: some View {
        // Il GeometryReader rispetta la safe area per leggerne gli inset reali;
        // solo la card la ignora. (Con `.ignoresSafeArea()` sul reader l'inset top
        // valeva 0 e "aperto" finiva sotto la Dynamic Island.)
        GeometryReader { geo in
            let m = Metrics(size: geo.size, insets: geo.safeAreaInsets, mapPeek: mapPeek)
            card(m, top: currentTop(m, base: detent, translation: translation))
                .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: detent)
        .onChange(of: isDragging) { _, dragging in
            // Gesto annullato dal sistema: torna alla posizione di riposo.
            if !dragging, translation != 0 { settle(to: detent, velocity: 0, distance: 0) }
        }
    }

    // MARK: - Card

    private func card(_ m: Metrics, top: CGFloat) -> some View {
        // 0 = flottante (chiusa/media) → 1 = a tutta larghezza (aperta).
        let progress = m.expansion(at: top)
        let inset = floatingInset * (1 - progress)
        // Parte di contenuto sotto il fondo della card a riposo: con questo padding
        // lo scroll arriva fino in fondo anche da media/chiusa.
        let hidden = max(0, m.top(for: detent) + floatingInset * (1 - m.expansion(at: m.top(for: detent))) - m.expandedTop)
        let shape = ConcentricRectangle(
            uniformTopCorners: .concentric(minimum: .fixed(CSRadius.lg)),
            uniformBottomCorners: .concentric(minimum: .fixed(CSRadius.lg)))

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
        // Altezza fissa: trascinando cambia solo la finestra visibile, il contenuto
        // (ScrollView) non si ri-impagina a ogni frame in verticale.
        .frame(height: m.height - m.expandedTop, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(cardBackground)
        .clipShape(shape)
        .contentShape(shape)
        .overlay {
            shape
                .stroke(LinearGradient(colors: [CSColor.specular.opacity(0.45), .clear],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { dragZone(m) }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 4)
        .padding(EdgeInsets(top: max(0, top), leading: inset, bottom: inset, trailing: inset))
        .frame(width: m.width, height: m.height)
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
            .onTapGesture { settle(to: detent.cycled, velocity: 0, distance: 0) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pannello")
            .accessibilityValue(detent.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: settle(to: detent.up, velocity: 0, distance: 0)
                case .decrement: settle(to: detent.down, velocity: 0, distance: 0)
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
                settle(to: target, velocity: velocity, distance: m.top(for: target) - current)
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

    /// Molla senza rimbalzo; un po' di bounce solo dopo un flick. La velocità del
    /// dito passa alla molla (relativa alla distanza) così non c'è uno stacco.
    private func settle(to target: SheetDetent, velocity: CGFloat, distance: CGFloat) {
        let animation: Animation = if reduceMotion {
            .easeOut(duration: 0.2)
        } else {
            .interpolatingSpring(duration: 0.38,
                                 bounce: abs(velocity) > 800 ? 0.15 : 0,
                                 initialVelocity: abs(distance) > 1
                                    ? min(max(velocity / distance, -12), 12) : 0)
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
        let width: CGFloat
        let height: CGFloat
        let expandedTop: CGFloat
        let mediumTop: CGFloat
        let collapsedTop: CGFloat

        init(size: CGSize, insets: EdgeInsets, mapPeek: CGFloat) {
            width = size.width + insets.leading + insets.trailing
            height = size.height + insets.top + insets.bottom
            // Sotto status bar / Dynamic Island, mai sopra.
            expandedTop = insets.top + 8
            mediumTop = insets.top + (height - insets.top) * mapPeek
            // Parte visibile da chiusa sopra la tab bar (maniglia + header), con
            // spazio minimo per la tab bar flottante in fondo alla card.
            let collapsedVisible: CGFloat = 84
            let tabBarClearance: CGFloat = 90
            collapsedTop = max(mediumTop, height - max(insets.bottom, tabBarClearance) - collapsedVisible)
        }

        func top(for detent: SheetDetent) -> CGFloat {
            switch detent {
            case .collapsed: collapsedTop
            case .medium: mediumTop
            case .expanded: expandedTop
            }
        }

        /// 0 da media in giù, 1 ad aperta (e oltre, nel rubber-band).
        func expansion(at top: CGFloat) -> CGFloat {
            let span = mediumTop - expandedTop
            guard span > 0 else { return 1 }
            return min(max((mediumTop - top) / span, 0), 1)
        }
    }
}
