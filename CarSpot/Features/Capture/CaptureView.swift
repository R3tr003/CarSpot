import SwiftUI
import PhotosUI

/// Capture screen. Live camera on device; photo-library fallback on the simulator
/// (no camera). Drives the real anonymize → recognize → confirm → save pipeline.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @State private var camera = CameraController()
    @State private var vm = CaptureViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var sweep = false

    var body: some View {
        ZStack {
            backdrop

            VStack {
                topBar
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
        }
        .task { await camera.prepare() }
        .task {
            // Debug: `-autoCapture YES` esegue la pipeline con un'immagine sintetica,
            // utile per verificare il flusso sul simulatore senza PHPicker.
            if UserDefaults.standard.bool(forKey: "autoCapture"), vm.phase == .aiming {
                await vm.process(image: Self.debugImage())
                if UserDefaults.standard.bool(forKey: "autoSave"), vm.phase == .result {
                    vm.save(into: context)
                }
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await vm.process(image: image)
                }
                pickerItem = nil
            }
        }
    }

    // MARK: Backdrop — live preview or staged camera feed

    @ViewBuilder private var backdrop: some View {
        if camera.isAvailable, vm.phase == .aiming {
            CameraPreview(session: camera.session).ignoresSafeArea()
            reticle
        } else {
            LinearGradient(colors: [Color(hex: 0x10131A), Color(hex: 0x05070A)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            GrainOverlay(opacity: 0.08).ignoresSafeArea()
            if vm.phase == .aiming { reticle }
        }
    }

    private var reticle: some View {
        GeometryReader { geo in
            let inset: CGFloat = 28
            let rect = CGRect(x: inset, y: geo.size.height * 0.22,
                              width: geo.size.width - inset * 2,
                              height: geo.size.height * 0.34)
            ZStack {
                ReticleCorners()
                    .stroke(CSColor.accent, style: .init(lineWidth: 3, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: CSColor.accent.opacity(0.6), radius: 8)
                if vm.phase == .processing {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, CSColor.accent.opacity(0.7), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: rect.width, height: 3)
                        .position(x: rect.midX, y: sweep ? rect.maxY : rect.minY)
                        .shadow(color: CSColor.accent, radius: 10)
                }
            }
        }
        .ignoresSafeArea()
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
        VStack(spacing: CSSpace.lg) {
            Text(camera.isAvailable
                 ? "Inquadra un'auto — frontale 3/4 per il match migliore"
                 : "Camera non disponibile sul simulatore — scegli una foto")
                .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
                .multilineTextAlignment(.center)

            if camera.isAvailable {
                Button { shoot() } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 74, height: 74)
                        Circle().strokeBorder(.white.opacity(0.4), lineWidth: 4).frame(width: 86, height: 86)
                    }
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(camera.isAvailable ? "Usa una foto" : "Scegli una foto")
                }
                .font(CSFont.body(16)).foregroundStyle(CSColor.ink)
                .padding(.vertical, 14).padding(.horizontal, 22)
                .glassEffect(.regular, in: .capsule)
            }
        }
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
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        Task {
            if let image = try? await camera.capturePhoto() {
                await vm.process(image: image)
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
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: true)) { sweep = true }
        }
        .onDisappear { sweep = false }
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
        .onAppear { camera.start() }
    }
}

/// Four L-shaped corner marks forming a camera reticle.
struct ReticleCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.18
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

#Preview { CaptureView().preferredColorScheme(.dark).modelContainer(for: StoredCard.self, inMemory: true) }
