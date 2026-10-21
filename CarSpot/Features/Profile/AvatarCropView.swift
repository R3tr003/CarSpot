import SwiftUI

/// Ritaglio dell'avatar a schermo intero: la foto scorre e si ingrandisce sotto un foro
/// circolare. La scala minima fa coprire tutto il cerchio alla foto (aspect fill), quindi
/// il ritaglio non ha mai bordi vuoti. `onConfirm` riceve il cerchio come rettangolo
/// normalizzato (0…1, origine in alto a sinistra) rispetto alla foto.
struct AvatarCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onConfirm: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxZoom: CGFloat = 4

    /// Stato a riposo (dopo l'ultimo gesto) e variazione del gesto in corso.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var drag: CGSize = .zero
    /// Diametro del foro, noto dopo il primo layout.
    @State private var diameter: CGFloat = 0

    private var pixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    var body: some View {
        ZStack {
            CSColor.base.ignoresSafeArea()
            cropLayer
            VStack(spacing: 0) {
                Text("Sposta e ridimensiona")
                    .font(CSFont.title(17))
                    .foregroundStyle(CSColor.ink)
                    .padding(.top, CSSpace.md)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Foto, maschera e gesti

    private var cropLayer: some View {
        GeometryReader { geo in
            let d = max(1, geo.size.width - 2 * CSSpace.lg)
            let base = baseSize(diameter: d)
            let liveZoom = zoom * pinch
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let hole = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: base.width, height: base.height)
                    .scaleEffect(liveZoom)
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                    .accessibilityLabel("Foto da ritagliare")
                    .accessibilityHint("Trascina per spostare, pizzica per ingrandire")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: setZoom(zoom + 0.5, diameter: d)
                        case .decrement: setZoom(zoom - 0.5, diameter: d)
                        @unknown default: break
                        }
                    }

                // Maschera scura con il foro circolare (riempimento pari-dispari).
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addEllipse(in: hole)
                }
                .fill(CSColor.base.opacity(0.7), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Circle()
                    .strokeBorder(CSColor.hairline, lineWidth: 1)
                    .frame(width: d, height: d)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(dragGesture(diameter: d).simultaneously(with: pinchGesture(diameter: d)))
            .onAppear { diameter = d }
            .onChange(of: d) { _, new in diameter = new }
        }
        .ignoresSafeArea()
    }

    private func dragGesture(diameter d: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                offset = CGSize(width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height)
                drag = .zero
                settle(diameter: d)
            }
    }

    private func pinchGesture(diameter d: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { pinch = $0.magnification }
            .onEnded { value in
                // Lo zoom dal vivo passa a quello a riposo senza salti, poi rientra nei limiti.
                zoom *= value.magnification
                pinch = 1
                setZoom(zoom, diameter: d)
            }
    }

    // MARK: - Geometria

    /// Dimensione della foto a zoom 1: il lato corto riempie esattamente il foro.
    private func baseSize(diameter d: CGFloat) -> CGSize {
        let scale = d / max(1, min(pixelSize.width, pixelSize.height))
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxZoom)
    }

    /// Sposta al massimo finché il foro resta dentro la foto.
    private func clampedOffset(_ value: CGSize, zoom: CGFloat, diameter d: CGFloat) -> CGSize {
        let base = baseSize(diameter: d)
        let maxX = max(0, (base.width * zoom - d) / 2)
        let maxY = max(0, (base.height * zoom - d) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX),
                      height: min(max(value.height, -maxY), maxY))
    }

    /// Fine gesto: riporta zoom e posizione nei limiti con una molla senza rimbalzo.
    private func settle(diameter d: CGFloat) {
        let target = clampedOffset(offset, zoom: zoom, diameter: d)
        if reduceMotion {
            offset = target
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0)) { offset = target }
        }
    }

    private func setZoom(_ value: CGFloat, diameter d: CGFloat) {
        let next = clampZoom(value)
        let target = clampedOffset(offset, zoom: next, diameter: d)
        if reduceMotion {
            zoom = next
            offset = target
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0)) {
                zoom = next
                offset = target
            }
        }
    }

    /// Il foro come rettangolo normalizzato rispetto alla foto.
    private func normalizedCrop() -> CGRect {
        let d = max(1, diameter)
        let base = baseSize(diameter: d)
        let width = base.width * zoom
        let height = base.height * zoom
        let off = clampedOffset(offset, zoom: zoom, diameter: d)
        // Angolo del foro rispetto all'angolo della foto: il centro della foto è spostato di `off`.
        let x = (width / 2 - d / 2 - off.width) / width
        let y = (height / 2 - d / 2 - off.height) / height
        let rect = CGRect(x: x, y: y, width: d / width, height: d / height)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Barra in basso

    private var bottomBar: some View {
        HStack(spacing: CSSpace.md) {
            GhostButton(title: "Annulla", action: onCancel)
            PrimaryButton(title: "Usa foto") {
                onConfirm(normalizedCrop())
            }
        }
        .padding(.horizontal, CSSpace.lg)
        .padding(.top, CSSpace.md)
        .safeAreaPadding(.bottom, CSSpace.md)
    }
}
