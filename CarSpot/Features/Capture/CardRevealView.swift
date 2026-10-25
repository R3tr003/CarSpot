import SwiftUI
import UIKit

/// Sfondo con la foto anonimizzata: stessi valori in `CaptureView` e nel volo, così il volo
/// parte esattamente da ciò che si vede.
enum PhotoBackdrop {
    static let blur: CGFloat = 6
    static let dim = 0.7
}

/// Il momento dopo il salvataggio: la foto scattata (già anonimizzata) vola dentro la carta,
/// la rarità si legge dal materiale, una sola vibrazione all'atterraggio. Si inclina col dito
/// (resistenza elastica oltre ~16°) e, su device, col giroscopio.
///
/// Sequenza (ms dall'apparizione): 120 parte il volo (molla senza rimbalzo, 560) · 680
/// atterraggio + vibrazione (+ auto‑inclinazione da Rara in su) · 770 pila dei doppioni ·
/// 880 nota nuova/doppione · 1040 ricompensa e azioni · 1290 avanza la barra del livello.
/// Tocco sullo sfondo = stato finale. Riduci movimento: solo dissolvenze, niente volo né
/// inclinazione (la vibrazione resta).
struct CardRevealView: View {
    let card: SpotCard
    /// Foto già anonimizzata, mai l'originale.
    let photo: UIImage?
    let info: RevealInfo
    var onAnother: () -> Void
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var flight = 0.0            // 0 = foto a schermo intero, 1 = nella finestra della carta
    @State private var flyVisible = true
    @State private var cardShown = false
    @State private var cardSettled = false     // scala 0,97 → 1
    @State private var ghostsShown = false
    @State private var noteShown = false
    @State private var footerShown = false
    @State private var barFraction: Double
    @State private var landed = 0              // trigger della vibrazione unica
    @State private var skipped = false
    @State private var tilt = CardTilt()
    @State private var motion = MotionManager()
    @State private var pitchBase: Double?
    /// Altezza reale di nota + ricompensa + bottoni (misurata): la carta prende lo spazio che resta.
    @State private var bottomHeight: CGFloat = 230

    init(card: SpotCard, photo: UIImage?, info: RevealInfo,
         onAnother: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.card = card
        self.photo = photo
        self.info = info
        self.onAnother = onAnother
        self.onDone = onDone
        // Se sale di livello la barra riparte da zero e arriva al punto raggiunto.
        _barFraction = State(initialValue: info.levelAfter > info.levelBefore ? 0 : info.fractionBefore)
    }

    // MARK: Costanti di motion

    /// Curva "out" dei testi (cubic-bezier 0,22 · 1 · 0,36 · 1 del prototipo).
    private static func out(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
    private static let flightSpring = Animation.spring(duration: 0.56, bounce: 0)
    /// Inclinazione automatica all'atterraggio, in gradi, solo da Rara in su.
    private var autoTilt: Double {
        guard !info.isRepeat else { return 0 }
        switch card.rarity {
        case .comune: return 0
        case .rara: return 7
        case .epica: return 8
        case .leggendaria: return 9
        }
    }

    /// Una sola vibrazione, più forte quanto più è rara. Una ripetizione resta leggera.
    private var landingFeedback: SensoryFeedback {
        if info.isRepeat { return .impact(weight: .light, intensity: 0.4) }
        switch card.rarity {
        case .comune: return .impact(weight: .light, intensity: 0.6)
        case .rara: return .impact(weight: .medium, intensity: 0.8)
        case .epica: return .impact(weight: .heavy, intensity: 0.85)
        case .leggendaria: return .impact(weight: .heavy, intensity: 1)
        }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, insets: geo.safeAreaInsets, bottomHeight: bottomHeight)
            ZStack(alignment: .top) {
                Color.clear
                stage(m)
                    .position(x: m.cardRect.midX, y: m.cardRect.midY)
                VStack(spacing: CSSpace.lg) {
                    note
                    footer
                }
                .padding(.horizontal, CSSpace.lg)
                .padding(.bottom, m.bottomPad)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
                .frame(maxHeight: .infinity, alignment: .bottom)

                if let photo, flyVisible {
                    FlyingPhoto(image: photo, from: m.screen, to: m.window, progress: flight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { skip() }
        }
        .ignoresSafeArea()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(landingFeedback, trigger: landed)
        .task(id: skipped) {
            if skipped || voiceOver { finish() } else { await play() }
        }
        .onChange(of: motion.roll) { _, _ in applyGyro() }
        .onChange(of: motion.pitch) { _, _ in applyGyro() }
        .onDisappear {
            tilt.stop()
            motion.stop()
        }
    }

    // MARK: Carta

    private func stage(_ m: Metrics) -> some View {
        ZStack {
            if info.isDuplicate {
                ghost(m, index: 2)
                ghost(m, index: 1)
            }
            SpotCardView(card: card,
                         roll: max(-1, min(1, tilt.x / CardTilt.limit)),
                         pitch: max(-1, min(1, tilt.y / CardTilt.limit)),
                         copies: info.isRepeat ? 1 : info.copyNumber)
                .frame(width: m.cardRect.width, height: m.cardRect.height)
        }
        .frame(width: m.cardRect.width, height: m.cardRect.height)
        .scaleEffect(cardSettled || reduceMotion ? 1 : 0.97)
        .opacity(cardShown ? 1 : 0)
        .rotation3DEffect(.degrees(tilt.x), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(tilt.y), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !reduceMotion else { return }
                    tilt.drag(translation: value.translation)
                }
                .onEnded { value in
                    guard !reduceMotion else { return }
                    tilt.release(velocity: value.velocity)
                }
        )
    }

    /// Una delle due carte "della pila" dietro la carta nuova di un doppione.
    private func ghost(_ m: Metrics, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: CSRadius.card, style: .continuous)
        let step = CGFloat(index)
        return shape
            .fill(CSColor.hero)
            .overlay { shape.strokeBorder(card.rarity.color.opacity(0.3), lineWidth: 1) }
            .frame(width: m.cardRect.width, height: m.cardRect.height)
            .opacity(ghostsShown ? (index == 1 ? 1 : 0.7) : 0)
            // Con Riduci movimento la posizione finale è fissa e cambia solo l'opacità.
            .offset(x: ghostsShown || reduceMotion ? 9 * step : 0,
                    y: ghostsShown || reduceMotion ? -9 * step : 0)
            .rotationEffect(.degrees(ghostsShown || reduceMotion ? 2 * Double(index) : 0))
            .accessibilityHidden(true)
    }

    // MARK: Nota, ricompensa, azioni

    private var noteLines: (title: String, detail: String) {
        if info.isRepeat {
            return (String(localized: "Già vista qui"),
                    String(localized: "Questa auto l'hai già catturata: nessun punto"))
        }
        if info.isDuplicate {
            return (String(localized: "La tua \(info.copyNumber)ª \(card.model)"),
                    String(localized: "Aggiunta alla pila · \(info.copyNumber) copie"))
        }
        // Sulla primissima carta "prima <Marca>" sarebbe solo un doppione della frase.
        let detail = info.isNewMake && info.cardNumber > 1
            ? String(localized: "Carta \(info.cardNumber) · prima \(card.make)")
            : String(localized: "Carta \(info.cardNumber)")
        return (String(localized: "Nuova nella collezione"), detail)
    }

    private var note: some View {
        let lines = noteLines
        return VStack(spacing: 3) {
            Text(verbatim: lines.title)
                .font(CSFont.title(17))
                .foregroundStyle(info.isRepeat ? CSColor.inkSecondary : CSColor.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(verbatim: lines.detail)
                .font(CSFont.caption(13))
                .foregroundStyle(CSColor.inkSecondary)
                .monospacedDigit()
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .opacity(noteShown ? 1 : 0)
        .offset(y: noteShown || reduceMotion ? 0 : 10)
    }

    private var footer: some View {
        VStack(spacing: CSSpace.md) {
            if !info.isRepeat { reward }
            let layout = typeSize >= .xLarge
                ? AnyLayout(VStackLayout(spacing: CSSpace.sm))
                : AnyLayout(HStackLayout(spacing: CSSpace.sm))
            layout {
                GhostButton(title: "Cattura un'altra", action: onAnother)
                PrimaryButton(title: "Fatto", haptic: false, action: onDone)
            }
        }
        .opacity(footerShown ? 1 : 0)
        .offset(y: footerShown || reduceMotion ? 0 : 10)
        .allowsHitTesting(footerShown)
    }

    /// "+N XP" statico (niente conteggio) e la barra del livello, che avanza una volta.
    private var reward: some View {
        VStack(spacing: CSSpace.sm) {
            HStack {
                if info.xpGained > 0 {
                    Text("+\(info.xpGained) PE")
                        .font(CSFont.numeric(15))
                        .foregroundStyle(CSColor.accentWarm)
                } else {
                    Text("Nessun punto per questa copia")
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.inkSecondary)
                }
                Spacer(minLength: CSSpace.sm)
                Text("Livello \(info.levelAfter) · \(info.xpInLevel) / \(info.xpForLevel) PE")
                    .font(CSFont.caption(13))
                    .monospacedDigit()
                    .foregroundStyle(CSColor.inkSecondary)
            }
            Capsule()
                .fill(CSColor.nested)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { track in
                        Capsule().fill(CSColor.accent)
                            .frame(width: track.size.width * max(0, min(1, barFraction)))
                    }
                }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.xpGained > 0
            ? String(localized: "Più \(info.xpGained) punti esperienza")
            : String(localized: "Nessun punto per questa copia"))
        .accessibilityValue("Livello \(info.levelAfter), \(info.xpInLevel) su \(info.xpForLevel)")
    }

    // MARK: Sequenza

    private func skip() {
        guard !skipped else { return }
        skipped = true
    }

    private func play() async {
        let clock = ContinuousClock()
        let start = clock.now
        func wait(_ ms: Int) async -> Bool {
            do { try await clock.sleep(until: start.advanced(by: .milliseconds(ms))) } catch { return false }
            return true
        }

        if reduceMotion || photo == nil {
            // Solo dissolvenze: la carta compare con la foto già dentro.
            withAnimation(.easeOut(duration: 0.25)) {
                flight = 1; flyVisible = false; cardShown = true; cardSettled = true
            }
            guard await wait(250) else { return }
            landed += 1
            if info.isDuplicate { withAnimation(.easeOut(duration: 0.2)) { ghostsShown = true } }
            guard await wait(450) else { return }
            withAnimation(.easeOut(duration: 0.25)) { noteShown = true }
            guard await wait(600) else { return }
            withAnimation(.easeOut(duration: 0.25)) { footerShown = true }
            guard await wait(750) else { return }
            withAnimation(.easeOut(duration: 0.4)) { barFraction = info.fractionAfter }
            return
        }

        // 1. Volo: la foto a schermo intero si rimpicciolisce nella finestra della carta.
        guard await wait(120) else { return }
        withAnimation(Self.flightSpring) { flight = 1; cardSettled = true }
        withAnimation(.easeOut(duration: 0.26).delay(0.22)) { cardShown = true }

        // 2. Atterraggio: vibrazione unica, la foto passa alla carta, la carta prende luce.
        guard await wait(680) else { return }
        landed += 1
        withAnimation(.easeOut(duration: 0.12)) { flyVisible = false }
        if autoTilt > 0 { tilt.setAuto(x: autoTilt, y: -autoTilt * 0.45) }

        if info.isDuplicate {
            guard await wait(770) else { return }
            withAnimation(Self.out(0.45)) { ghostsShown = true }
        }

        // 3. Nota nuova/doppione, poi ricompensa e azioni.
        guard await wait(880) else { return }
        withAnimation(Self.out(0.38)) { noteShown = true }
        guard await wait(1040) else { return }
        withAnimation(Self.out(0.38)) { footerShown = true }
        guard await wait(1060) else { return }
        tilt.setAuto(x: 0, y: 0)
        guard await wait(1290) else { return }
        withAnimation(Self.out(0.8)) { barFraction = info.fractionAfter }

        guard await wait(1500) else { return }
        enableGyro()
    }

    /// Stato finale subito (tocco sullo sfondo, VoiceOver).
    private func finish() {
        if landed == 0 { landed += 1 }   // la vibrazione unica c'è comunque
        withAnimation(.easeOut(duration: 0.15)) {
            flight = 1; flyVisible = false; cardShown = true; cardSettled = true
            ghostsShown = info.isDuplicate; noteShown = true; footerShown = true
            barFraction = info.fractionAfter
        }
        tilt.setAuto(x: 0, y: 0)
        enableGyro()
    }

    // MARK: Giroscopio

    private func enableGyro() {
        guard !reduceMotion, pitchBase == nil else { return }
        motion.start()
        pitchBase = motion.pitch
        applyGyro()
    }

    private func applyGyro() {
        guard let base = pitchBase, !reduceMotion else { return }
        // Come il dettaglio carta: ±8° a fondo scala. Il beccheggio è relativo a come si tiene il telefono.
        let pitch = max(-1, min(1, motion.pitch - base))
        tilt.setGyro(x: motion.roll * 8, y: -pitch * 8)
    }
}

// MARK: - Geometria

/// Misure del layout. La carta occupa lo spazio tra la barra in alto e il blocco in basso (nota,
/// ricompensa, bottoni), la cui altezza è misurata: i bottoni restano sempre raggiungibili. La
/// finestra foto è una stima della posizione di `CardPhoto` dentro `SpotCardView` (96 pt, centrata
/// tra intestazione e piè): il volo si chiude con una dissolvenza di 120 ms che copre scarti di
/// qualche punto.
private struct Metrics {
    static let cardAspect: CGFloat = 0.7          // come SpotCardView
    static let windowHeight: CGFloat = 96         // altezza massima di CardPhoto

    let screen: CGRect
    let bottomPad: CGFloat
    let cardRect: CGRect
    let window: CGRect

    init(size: CGSize, insets: EdgeInsets, bottomHeight: CGFloat) {
        screen = CGRect(origin: .zero, size: size)
        // Sotto la barra in alto (titolo + X) della cattura.
        let top = insets.top + CSSpace.lg + CSSize.minTap + CSSpace.md
        bottomPad = max(insets.bottom, CSSpace.md) + CSSpace.sm
        let available = max(0, size.height - top - bottomHeight - CSSpace.lg)
        let width = max(140, min(260, size.width - 120, available * Self.cardAspect))
        let height = width / Self.cardAspect
        // Centrata nello spazio libero (mai sotto la barra in alto).
        let y = top + max(0, (available - height) / 2)
        cardRect = CGRect(x: (size.width - width) / 2, y: y, width: width, height: height)
        window = CGRect(x: cardRect.minX + CSSpace.md,
                        y: cardRect.midY + 16 - Self.windowHeight / 2,
                        width: width - CSSpace.md * 2,
                        height: Self.windowHeight)
    }
}

// MARK: - Foto che vola

/// La foto anonimizzata che passa dallo schermo intero (scurita e sfocata come lo sfondo di
/// `CaptureView`) alla finestra della carta (nitida, angoli del riquadro foto). `progress`
/// è animabile: ogni fotogramma ricalcola cornice, sfocatura e velo.
private nonisolated struct FlyingPhoto: View, Animatable {
    let image: UIImage
    let from: CGRect
    let to: CGRect
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(progress) }

    var body: some View {
        let rect = CGRect(x: lerp(from.minX, to.minX), y: lerp(from.minY, to.minY),
                          width: lerp(from.width, to.width), height: lerp(from.height, to.height))
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .blur(radius: PhotoBackdrop.blur * (1 - progress), opaque: true)
            .overlay(Color.black.opacity(PhotoBackdrop.dim * (1 - progress)))
            .clipShape(RoundedRectangle(cornerRadius: lerp(0, CSRadius.sm), style: .continuous))
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Inclinazione

/// Inclinazione della carta come molla critica guidata dal display: segue il dito 1:1 con
/// resistenza elastica oltre `limit` gradi, al rilascio torna a riposo ereditando la velocità.
/// L'inclinazione automatica e quella del giroscopio spostano il punto di riposo.
@MainActor
@Observable
private final class CardTilt {
    /// Gradi oltre i quali il dito incontra resistenza.
    static let limit = 16.0
    /// Pixel di trascinamento per grado.
    private static let pointsPerDegree = 6.0
    private static let stiffness = 170.0

    /// Rotazione attorno a Y e a X, in gradi.
    private(set) var x = 0.0
    private(set) var y = 0.0

    @ObservationIgnored private var vx = 0.0
    @ObservationIgnored private var vy = 0.0
    @ObservationIgnored private var autoX = 0.0
    @ObservationIgnored private var autoY = 0.0
    @ObservationIgnored private var gyroX = 0.0
    @ObservationIgnored private var gyroY = 0.0
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var startX = 0.0
    @ObservationIgnored private var startY = 0.0
    @ObservationIgnored private var lastTick = 0.0
    @ObservationIgnored private var link: CADisplayLink?

    // Dito

    func drag(translation: CGSize) {
        if !dragging {
            dragging = true
            startX = x
            startY = y
            vx = 0
            vy = 0
        }
        x = Self.resist(startX + translation.width / Self.pointsPerDegree)
        y = Self.resist(startY - translation.height / Self.pointsPerDegree)
    }

    func release(velocity: CGSize) {
        guard dragging else { return }
        dragging = false
        // Velocità del dito in gradi/s, attenuata dalla resistenza (derivata della tangente iperbolica).
        let ex = 1 - pow(x / Self.limit, 2)
        let ey = 1 - pow(y / Self.limit, 2)
        vx = max(-400, min(400, velocity.width / Self.pointsPerDegree * ex))
        vy = max(-400, min(400, -velocity.height / Self.pointsPerDegree * ey))
        wake()
    }

    // Punto di riposo

    func setAuto(x: Double, y: Double) {
        autoX = x
        autoY = y
        wake()
    }

    func setGyro(x: Double, y: Double) {
        gyroX = x
        gyroY = y
        wake()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    // Molla

    private static func resist(_ value: Double) -> Double {
        limit * tanh(value / limit)
    }

    private func wake() {
        if link == nil {
            let proxy = DisplayLinkProxy()
            proxy.owner = self
            let newLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
        lastTick = CACurrentMediaTime()
        link?.isPaused = false
    }

    fileprivate func step(_ link: CADisplayLink) {
        let dt = min(max(link.timestamp - lastTick, 0), 1.0 / 30)
        lastTick = link.timestamp
        guard !dragging else { return }
        let k = Self.stiffness
        let c = 2 * k.squareRoot()          // smorzamento critico: niente rimbalzo
        let goalX = autoX + gyroX
        let goalY = autoY + gyroY
        vx += (-k * (x - goalX) - c * vx) * dt
        vy += (-k * (y - goalY) - c * vy) * dt
        x += vx * dt
        y += vy * dt
        let settled = abs(x - goalX) < 0.01 && abs(y - goalY) < 0.01 && abs(vx) < 0.05 && abs(vy) < 0.05
        if settled {
            x = goalX
            y = goalY
            vx = 0
            vy = 0
            link.isPaused = true
        }
    }
}

/// Il display link trattiene il suo target: questo ponte tiene solo un riferimento debole.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: CardTilt?

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.step(link)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CardRevealView(
            card: SpotCard.sample[1], photo: nil,
            info: RevealInfo(isRepeat: false, copyNumber: 3, cardNumber: 13, isNewMake: false,
                             xpGained: 32, levelBefore: 1, levelAfter: 1,
                             fractionBefore: 0.18, fractionAfter: 0.5, xpInLevel: 50, xpForLevel: 100),
            onAnother: {}, onDone: {})
    }
    .preferredColorScheme(.dark)
}
