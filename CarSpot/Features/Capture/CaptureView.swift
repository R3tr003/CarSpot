import SwiftUI
import PhotosUI
import SwiftData

/// Geometria del mirino e misure di layout locali (non token del design system).
private enum Viewfinder {
    static let inset: CGFloat = 32          // margine laterale
    static let aspect: CGFloat = 0.62       // altezza / larghezza
    static let centerY: CGFloat = 0.42      // centro, in frazione dell'altezza schermo
    static let arm: CGFloat = 22            // tratto dritto dopo l'arco
    static let lineWidth: CGFloat = 2
    static let topScrim: CGFloat = 140      // altezza del gradiente scuro sotto la barra in alto
    static let actionMaxWidth: CGFloat = 280 // larghezza dei bottoni secondari sopra la camera
}

/// Capture screen. Live camera on device; photo-library fallback on the simulator
/// (no camera). Drives the real anonymize → recognize → confirm → save pipeline.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var vm = CaptureViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var isVisible = false
    @State private var shutterBusy = false
    @State private var flashCount = 0
    @State private var showHint = true

    var body: some View {
        ZStack {
            backdrop

            // Il reveal occupa tutto lo schermo; la barra in alto resta sopra.
            ZStack {
                if vm.phase == .saved, let card = vm.savedCard, let info = vm.revealInfo {
                    CardRevealView(card: card, photo: vm.anonymizedImage, info: info,
                                   onAnother: { vm.reset() }, onDone: { dismiss() })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: vm.phase == .saved)

            VStack(spacing: CSSpace.md) {
                topBar
                if showHint, camera.isAvailable, vm.phase == .aiming {
                    hint.transition(.opacity)
                }
                Spacer()
                VStack(spacing: CSSpace.md) {
                    if let message = vm.errorMessage {
                        errorBanner(message)
                    }
                    phasePanel
                }
                .animation(Self.phaseSpring, value: vm.errorMessage)
            }
            .padding(CSSpace.lg)

            flashOverlay
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flashCount)
        .sensoryFeedback(trigger: vm.phase) { _, new in phaseFeedback(new) }
        .sensoryFeedback(.error, trigger: vm.errorID)
        .sensoryFeedback(trigger: vm.selected) { old, new in
            // Solo cambio di scelta: la preselezione all'arrivo dei risultati non vibra.
            old != nil && new != nil ? .selection : nil
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onAppear {
            isVisible = true
            Task { await camera.prepare() }
        }
        .onDisappear {
            isVisible = false
            camera.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            // Rilegge il permesso (può essere cambiato da Impostazioni) e riavvia la sessione.
            guard isVisible, phase == .active else { return }
            Task { await camera.prepare() }
        }
        .onChange(of: vm.phase) { _, phase in
            if phase == .aiming { camera.start() }
        }
        .task {
            // Il suggerimento sparisce da solo dopo 3 s.
            showHint = true
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showHint = false }
        }
        .task {
            // Debug: `-autoCapture YES` esegue la pipeline con un'immagine sintetica,
            // utile per verificare il flusso sul simulatore senza PHPicker.
            if UserDefaults.standard.bool(forKey: "autoCapture"), vm.phase == .aiming {
                await vm.process(image: Self.debugImage(), source: "auto")
                if UserDefaults.standard.bool(forKey: "autoSave"), vm.phase == .result {
                    await vm.save(into: context)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await vm.process(data: data, source: "library")
                    } else {
                        vm.report(.photoUnreadable)
                    }
                } catch {
                    AppServices.errors.record(error, area: .capture, step: "load_library_photo")
                    vm.report(.photoUnreadable)
                }
                pickerItem = nil
            }
        }
    }

    // MARK: Fasi, haptic, transizioni

    private static let phaseSpring = Animation.spring(duration: 0.3, bounce: 0)

    /// Transizione dei pannelli di fase: dissolvenza + 8 pt di scarto (solo opacità con Reduce Motion).
    private var phaseTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    /// Un solo pannello per volta; ZStack così durante lo scambio non si impilano.
    private var phasePanel: some View {
        ZStack(alignment: .bottom) {
            switch vm.phase {
            case .aiming: aimingControls.transition(phaseTransition)
            case .processing: processingHUD.transition(phaseTransition)
            case .result: resultPanel.transition(phaseTransition)
            case .saved: EmptyView()   // lo schermo intero è CardRevealView
            }
        }
        .animation(Self.phaseSpring, value: vm.phase)
    }

    /// Haptic al cambio di fase: avviso se poco sicuri, selezione quando arrivano i risultati.
    private func phaseFeedback(_ phase: CaptureViewModel.Phase) -> SensoryFeedback? {
        switch phase {
        case .result:
            return vm.isLowConfidence ? .warning : .selection
        case .saved:
            return nil   // l'unica vibrazione del reveal è all'atterraggio (CardRevealView)
        case .aiming, .processing:
            return nil
        }
    }

    // MARK: Backdrop — live preview, fermo-immagine, mirino

    @ViewBuilder private var backdrop: some View {
        if camera.isAvailable {
            CameraPreview(session: camera.session).ignoresSafeArea()
        } else {
            dimBackdrop
            if camera.status == .idle || camera.status == .configuring {
                ProgressView().tint(CSColor.inkSecondary)
            }
        }

        // Fermo-immagine: miniatura sfocata sotto l'HUD (mai uno schermo "morto").
        ZStack {
            if vm.phase != .aiming {
                frozenBackdrop.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.phase)

        if vm.phase == .aiming || vm.phase == .processing {
            viewfinder
        }

        // Gradiente scuro sotto la barra in alto: contrasto del titolo sopra la camera.
        LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: Viewfinder.topScrim)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var dimBackdrop: some View {
        ZStack {
            LinearGradient(colors: [CSColor.surface, CSColor.base],
                           startPoint: .top, endPoint: .bottom)
            GrainOverlay(opacity: 0.08)
        }
        .ignoresSafeArea()
    }

    /// La foto già anonimizzata a schermo intero, scurita e appena sfocata: resta fino al reveal,
    /// dove vola dentro la carta. Prima dell'anonimizzazione solo lo sfondo scuro (mai l'originale).
    private var frozenBackdrop: some View {
        ZStack {
            dimBackdrop
            if let photo = vm.anonymizedImage {
                Color.clear
                    .overlay {
                        Image(uiImage: photo)
                            .resizable().scaledToFill()
                            .blur(radius: PhotoBackdrop.blur, opaque: true)
                            .overlay(Color.black.opacity(PhotoBackdrop.dim))
                    }
                    .clipped()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.anonymizedImage != nil)
        .accessibilityHidden(true)
    }

    /// Vignettatura morbida + quattro archi d'angolo, centrati sopra la metà schermo.
    private var viewfinder: some View {
        GeometryReader { geo in
            let width = geo.size.width - Viewfinder.inset * 2
            let height = width * Viewfinder.aspect
            ZStack {
                RadialGradient(colors: [.clear, .black.opacity(0.45)],
                               center: UnitPoint(x: 0.5, y: Viewfinder.centerY),
                               startRadius: width / 2,
                               endRadius: max(geo.size.width, geo.size.height) * 0.75)
                    .allowsHitTesting(false)

                ViewfinderFrame(isProcessing: vm.phase == .processing)
                    .frame(width: width, height: height)
                    .position(x: geo.size.width / 2, y: geo.size.height * Viewfinder.centerY)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Lampo bianco breve al click dell'otturatore (comparsa immediata, poi ease-out ~180 ms).
    private var flashOverlay: some View {
        Color.white
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: 0.0, trigger: flashCount) { content, value in
                content.opacity(value)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(reduceMotion ? 0.25 : 0.6, duration: 0.02)
                    CubicKeyframe(0.0, duration: 0.16)
                }
            }
            .accessibilityHidden(true)
    }

    private var hint: some View {
        Text("Inquadra l'auto di 3/4")
            .font(CSFont.caption()).foregroundStyle(CSColor.ink)
            .padding(.vertical, CSSpace.sm).padding(.horizontal, CSSpace.md)
            .glassEffect(.regular, in: .capsule)
    }

    /// Titolo e chiusura: la cattura si apre a tutto schermo sopra il pannello.
    private var topBar: some View {
        HStack {
            Text("Cattura").eyebrow(CSColor.accent)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(CSFont.title(17))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: CSSize.minTap, height: CSSize.minTap)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(CSPressStyle())
            .accessibilityLabel("Chiudi")
        }
    }

    // MARK: Errore

    /// Banner sopra i controlli: icona, frase semplice, "Riprova". Sparisce da solo dopo ~5 s.
    private func errorBanner(_ message: String) -> some View {
        GlassPanel(cornerRadius: CSRadius.sm, padding: CSSpace.md) {
            HStack(spacing: CSSpace.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CSColor.accentWarm)
                    .accessibilityHidden(true)
                Text(message)
                    .font(CSFont.caption(13)).foregroundStyle(CSColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await vm.retry(into: context) }
                } label: {
                    Text("Riprova")
                        .font(CSFont.caption(13)).foregroundStyle(CSColor.accent)
                        .frame(minWidth: CSSize.minTap, minHeight: CSSize.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CSPressStyle())
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        .task(id: vm.errorID) {
            // Con VoiceOver il banner resta: l'annuncio non basta a leggere e agire in 5 s.
            guard !UIAccessibility.isVoiceOverRunning else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            vm.dismissError()
        }
    }

    // MARK: Aiming

    private var aimingControls: some View {
        VStack(spacing: CSSpace.lg) {
            switch camera.status {
            case .ready:
                Button { shoot() } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 74, height: 74)
                        Circle().strokeBorder(.white.opacity(0.4), lineWidth: 4).frame(width: 86, height: 86)
                    }
                    .frame(minWidth: 86, minHeight: 86)
                }
                .buttonStyle(ShutterButtonStyle())
                .disabled(shutterBusy || camera.isCapturing)
                .accessibilityLabel("Scatta")
                .accessibilityHint("Scatta e riconosce l'auto")
            case .denied:
                VStack(spacing: CSSpace.md) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28))   // icona decorativa grande, dimensione fissa
                        .foregroundStyle(CSColor.inkSecondary)
                        .accessibilityHidden(true)
                    Text("Accesso alla fotocamera negato")
                        .font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                        .multilineTextAlignment(.center)
                    Text("Serve per inquadrare e riconoscere le auto: la foto resta sul telefono finché non è anonimizzata.")
                        .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                        .multilineTextAlignment(.center)
                    GhostButton(title: "Apri Impostazioni") { openSettings() }
                }
                .frame(maxWidth: Viewfinder.actionMaxWidth)
            case .unavailable:
                Text("Fotocamera non disponibile: scegli una foto")
                    .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                    .multilineTextAlignment(.center)
            case .idle, .configuring:
                EmptyView()
            }

            GhostButton(title: photoButtonTitle,
                        icon: "photo.on.rectangle.angled") { showPicker = true }
                .frame(maxWidth: Viewfinder.actionMaxWidth)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// Synthetic image for the `-autoCapture` debug path.
    private static func debugImage() -> UIImage {
        let size = CGSize(width: 800, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1).cgColor,
                          UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
            let symbol = UIImage(systemName: "car.side.fill")?
                .withTintColor(.systemTeal, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 250, y: 220, width: 300, height: 160))
        }
    }

    private func shoot() {
        guard !shutterBusy, vm.phase == .aiming else { return }
        shutterBusy = true
        flashCount += 1   // lampo + haptic nello stesso frame del tap
        withAnimation(.easeOut(duration: 0.2)) { showHint = false }
        Task {
            defer { shutterBusy = false }
            do {
                let data = try await camera.capturePhoto()
                await vm.process(data: data, source: "camera")
            } catch {
                vm.report(.captureFailed)
            }
        }
    }

    // MARK: Processing

    private var processingHUD: some View {
        GlassPanel(cornerRadius: CSRadius.md) {
            HStack(spacing: CSSpace.md) {
                ProgressView().tint(CSColor.accent)
                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    Text("Riconoscimento in corso").font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                    Text("Offusco targhe e volti · cerco il modello")
                        .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Result — confirm a candidate

    /// Dentro uno ScrollView solo quando non entra (testo grande): i bottoni non si tagliano mai.
    private var resultPanel: some View {
        FitScroll { resultContent }
    }

    private var resultContent: some View {
        VStack(spacing: CSSpace.md) {
            // La foto è già lo sfondo a schermo intero: qui solo la scelta del modello.
            Surface(.group) {
                VStack(alignment: .leading, spacing: CSSpace.sm) {
                    Text(matchTitle)
                        .eyebrow(CSColor.accent)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(vm.candidates) { candidate in
                        candidateRow(candidate)
                    }
                    if vm.isLowConfidence {
                        SurfaceDivider()
                        noneOfThemRow
                    }
                    Text("L'anno è una stima e può essere corretto in seguito.")
                        .font(CSFont.caption(11)).foregroundStyle(CSColor.inkSecondary)
                        .padding(.top, CSSpace.xxs)
                }
            }

            PrimaryButton(title: "Aggiungi alla collezione", icon: "checkmark",
                          haptic: false) {   // il reveal ha già la sua vibrazione
                Task { await vm.save(into: context) }
            }
            .disabled(vm.selected == nil || vm.isSaving)
            .opacity(vm.selected == nil || vm.isSaving ? 0.4 : 1)
            .accessibilityHint(selectionHint)

            GhostButton(title: "Riprova", icon: "arrow.triangle.2.circlepath") { vm.reset() }
        }
    }

    private var matchTitle: LocalizedStringKey {
        vm.isLowConfidence ? "Non siamo sicuri" : "Confermi il match?"
    }

    private var selectionHint: LocalizedStringKey {
        vm.selected == nil ? "Scegli prima una corrispondenza" : ""
    }

    private var photoButtonTitle: LocalizedStringKey {
        camera.isAvailable ? "Usa una foto" : "Scegli una foto"
    }

    private func candidateRow(_ candidate: VehicleCandidate) -> some View {
        let isSelected = vm.selected == candidate
        let level = candidate.confidenceLevel
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { vm.selected = candidate }
        } label: {
            HStack(spacing: CSSpace.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? CSColor.accent : CSColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    Text(candidate.title).font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                        .lineLimit(2)
                    if let year = candidate.yearEstimate {
                        Text("Anno stimato \(String(year))")
                            .font(CSFont.caption(11)).foregroundStyle(CSColor.inkSecondary)
                    }
                }
                Spacer(minLength: CSSpace.sm)
                Text(level.label)
                    .font(CSFont.caption(13))
                    .foregroundStyle(level == .alta ? CSColor.accent : CSColor.inkSecondary)
                    .accessibilityHidden(true)   // a voce si legge la percentuale
            }
            .frame(minHeight: CSSize.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue("\(candidate.confidencePercent) percento")
    }

    /// Bassa confidenza: via d'uscita se nessun candidato è quello giusto.
    private var noneOfThemRow: some View {
        Button { vm.reset() } label: {
            HStack(spacing: CSSpace.md) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(CSColor.inkSecondary)
                    .accessibilityHidden(true)
                Text("Nessuna di queste").font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                Spacer()
            }
            .frame(minHeight: CSSize.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Torna al mirino")
    }
}

#Preview { CaptureView().preferredColorScheme(.dark).modelContainer(for: StoredCard.self, inMemory: true) }

// MARK: - Mirino

/// Quattro archi d'angolo che seguono un rettangolo arrotondato: nessun rettangolo
/// netto, nessun glow. In elaborazione pulsano piano (scala 1↔1.03, opacità 0.85↔0.5).
private struct ViewfinderFrame: View {
    let isProcessing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var animates: Bool { isProcessing && !reduceMotion }

    var body: some View {
        CornerArcs(radius: CSRadius.lg, arm: Viewfinder.arm)
            .stroke(.white.opacity(0.85),
                    style: .init(lineWidth: Viewfinder.lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.35), radius: 3)   // stacca gli archi dai fondi chiari
            .scaleEffect(animates && pulse ? 1.03 : 1)
            .opacity(opacity)
            .animation(animates ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .smooth(duration: 0.25),
                       value: pulse)
            .onAppear { pulse = animates }
            .onChange(of: animates) { _, on in pulse = on }
    }

    private var opacity: Double {
        guard isProcessing else { return 1 }       // già incluso 0.85 nello stroke
        if reduceMotion { return 0.6 / 0.85 }      // statico a 0.6 complessivo
        return pulse ? 0.5 / 0.85 : 1              // 0.85 ↔ 0.5 complessivo
    }
}

/// Un arco per angolo (raggio `radius`) più un tratto dritto di `arm` per lato.
private struct CornerArcs: Shape {
    let radius: CGFloat
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = radius, a = arm
        var p = Path()
        // In alto a sinistra
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + a))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r + a, y: rect.minY))
        // In alto a destra
        p.move(to: CGPoint(x: rect.maxX - r - a, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + a))
        // In basso a destra
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - a))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - r - a, y: rect.maxY))
        // In basso a sinistra
        p.move(to: CGPoint(x: rect.minX + r + a, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - a))
        return p
    }
}

/// Otturatore: cerchio bianco con feedback di pressione a molla.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

/// Mostra il contenuto così com'è se entra; altrimenti lo mette in uno ScrollView
/// (testo grande / schermi piccoli) senza rimbalzo quando non serve.
private struct FitScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}
