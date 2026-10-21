import SwiftUI
import PhotosUI
import SwiftData

/// Geometria del mirino (valori di layout locali, non token del design system).
private enum Viewfinder {
    static let inset: CGFloat = 32          // margine laterale
    static let aspect: CGFloat = 0.62       // altezza / larghezza
    static let centerY: CGFloat = 0.42      // centro, in frazione dell'altezza schermo
    static let arm: CGFloat = 22            // tratto dritto dopo l'arco
    static let lineWidth: CGFloat = 2
}

/// Capture screen. Live camera on device; photo-library fallback on the simulator
/// (no camera). Drives the real anonymize → recognize → confirm → save pipeline.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = CameraController()
    @State private var vm = CaptureViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isVisible = false
    @State private var shutterBusy = false
    @State private var flashCount = 0
    @State private var showHint = true

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: CSSpace.md) {
                topBar
                if showHint, camera.isAvailable, vm.phase == .aiming {
                    hint.transition(.opacity)
                }
                Spacer()
                switch vm.phase {
                case .aiming: aimingControls
                case .processing: processingHUD
                case .result: resultPanel
                case .saved: savedPanel
                }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 70)

            flashOverlay
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flashCount)
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
                    vm.save(into: context)
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
                        vm.errorMessage = "Impossibile leggere la foto."
                    }
                } catch {
                    vm.errorMessage = "Impossibile leggere la foto."
                }
                pickerItem = nil
            }
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
    }

    private var dimBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x10131A), Color(hex: 0x05070A)],
                           startPoint: .top, endPoint: .bottom)
            GrainOverlay(opacity: 0.08)
        }
        .ignoresSafeArea()
    }

    private var frozenBackdrop: some View {
        ZStack {
            dimBackdrop
            if let thumb = vm.previewImage {
                Color.clear
                    .overlay {
                        Image(uiImage: thumb)
                            .resizable().scaledToFill()
                            .blur(radius: 28, opaque: true)
                            .overlay(Color.black.opacity(0.4))
                    }
                    .clipped()
                    .ignoresSafeArea()
            }
        }
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

    private var topBar: some View {
        HStack {
            Text("Cattura").eyebrow(CSColor.accent)
            Spacer()
            if let error = vm.errorMessage {
                Text(error).font(CSFont.caption(11)).foregroundStyle(.orange)
                    .lineLimit(2).frame(maxWidth: 200, alignment: .trailing)
            }
        }
    }

    // MARK: Aiming

    private var aimingControls: some View {
        // Copia locale: la closure `label` di PhotosPicker non è main-actor.
        let pickerTitle = camera.isAvailable ? "Usa una foto" : "Scegli una foto"
        return VStack(spacing: CSSpace.lg) {
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
            case .denied:
                VStack(spacing: CSSpace.md) {
                    Text("Accesso alla fotocamera negato")
                        .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button { openSettings() } label: {
                        Text("Apri Impostazioni")
                            .font(CSFont.body(16)).foregroundStyle(CSColor.ink)
                            .padding(.vertical, 14).padding(.horizontal, 22)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            case .unavailable:
                Text("Fotocamera non disponibile — scegli una foto")
                    .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                    .multilineTextAlignment(.center)
            case .idle, .configuring:
                EmptyView()
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(pickerTitle)
                }
                .font(CSFont.body(16)).foregroundStyle(CSColor.ink)
                .padding(.vertical, 14).padding(.horizontal, 22)
                .glassEffect(.regular, in: .capsule)
            }
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
                vm.errorMessage = "Scatto non riuscito. Riprova."
            }
        }
    }

    // MARK: Processing

    private var processingHUD: some View {
        GlassPanel(cornerRadius: CSRadius.md) {
            HStack(spacing: CSSpace.md) {
                ProgressView().tint(CSColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Riconoscimento in corso").font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                    Text("Offusco targhe e volti · cerco il modello")
                        .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Result — confirm a candidate

    private var resultPanel: some View {
        VStack(spacing: CSSpace.md) {
            if let img = vm.anonymizedImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: CSRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CSRadius.md).strokeBorder(CSColor.hairline))
            }

            GlassPanel(cornerRadius: CSRadius.md) {
                VStack(alignment: .leading, spacing: CSSpace.sm) {
                    Text("Confermi il match?").eyebrow(CSColor.accent)
                    ForEach(vm.candidates) { candidate in
                        candidateRow(candidate)
                    }
                    Text("L'anno è una stima e può essere corretto in seguito.")
                        .font(CSFont.caption(11)).foregroundStyle(CSColor.inkTertiary)
                        .padding(.top, 2)
                }
            }

            PrimaryButton(title: "Aggiungi alla collezione", icon: "checkmark",
                          gradient: (vm.selected.map {
                              RarityEngine.assess(make: $0.make, model: $0.model,
                                                  year: $0.yearEstimate).rarity.gradient
                          } ?? Rarity.rara.gradient)) {
                vm.save(into: context)
            }
            GhostButton(title: "Riprova", icon: "arrow.triangle.2.circlepath") { vm.reset() }
        }
    }

    private func candidateRow(_ candidate: VehicleCandidate) -> some View {
        let isSelected = vm.selected == candidate
        return Button {
            vm.selected = candidate
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: CSSpace.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? CSColor.accent : CSColor.inkTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.title).font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                    if let year = candidate.yearEstimate {
                        Text("Anno stimato \(String(year))")
                            .font(CSFont.caption(11)).foregroundStyle(CSColor.inkSecondary)
                    }
                }
                Spacer()
                Text("\(candidate.confidencePercent)%")
                    .font(CSFont.numeric(14))
                    .foregroundStyle(candidate.confidence > 0.8 ? CSColor.accent : CSColor.inkSecondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Saved

    private var savedPanel: some View {
        GlassPanel {
            VStack(spacing: CSSpace.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44)).foregroundStyle(CSColor.accent)
                Text("Aggiunta alla collezione!").font(CSFont.title(18)).foregroundStyle(CSColor.ink)
                if let c = vm.selected {
                    Text(c.title).font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                }
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                    Text("+\(vm.lastReward) PE").font(CSFont.numeric(15))
                }
                .foregroundStyle(CSColor.accentWarm)
                PrimaryButton(title: "Cattura un'altra", icon: "camera.fill") { vm.reset() }
            }
            .frame(maxWidth: .infinity)
        }
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
