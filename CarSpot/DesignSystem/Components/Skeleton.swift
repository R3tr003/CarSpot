import SwiftUI

/// Skeleton di caricamento: blocchi `nested` nella forma del contenuto che arriva, con una
/// pulsazione lenta (opacità 0,55 ↔ 1, ciclo 2,4 s). La fase segue l'orologio, così tutti gli
/// skeleton a schermo respirano insieme anche se compaiono in momenti diversi.
/// Con Riduci movimento restano fermi. Mai spinner al posto di un contenuto con una forma.

/// Blocco segnaposto (immagine, numero, pulsante). Statico: la pulsazione la dà
/// `.skeletonLoading()` sul gruppo, o `.skeletonPulse()` se il blocco è da solo.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = CSRadius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CSColor.nested)
            .accessibilityHidden(true)
    }
}

/// Riga di testo finta: capsula larga `width` (nil = tutta la riga).
struct SkeletonLine: View {
    var width: CGFloat?
    var height: CGFloat = 10

    var body: some View {
        Capsule()
            .fill(CSColor.nested)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// `KPIStrip` in caricamento: stessa superficie e divisori, etichette e numeri finti.
struct KPIStripSkeleton: View {
    var count = 3

    var body: some View {
        Surface(.group, padding: nil) {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(CSColor.divider).frame(width: 1).padding(.vertical, CSSpace.sm)
                    }
                    VStack(alignment: .leading, spacing: CSSpace.xs) {
                        SkeletonLine(width: 56)
                        Spacer(minLength: CSSpace.xs)
                        SkeletonBlock(cornerRadius: 6).frame(width: 34, height: 22)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(CSSpace.md)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .skeletonLoading()
    }
}

/// Pulsazione condivisa, legata all'orologio (30 fps come le altre animazioni continue).
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 2.4
    private static let low = 0.55

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.8)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate / Self.period * 2 * .pi
                content.opacity(Self.low + (1 - Self.low) * (0.5 + 0.5 * sin(phase)))
            }
        }
    }
}

extension View {
    /// Solo la pulsazione (blocco isolato dentro un contenuto vero, es. un'immagine che arriva).
    func skeletonPulse() -> some View {
        modifier(SkeletonPulse())
    }

    /// Gruppo di skeleton: pulsazione unica e un solo elemento "Caricamento" per VoiceOver.
    func skeletonLoading() -> some View {
        modifier(SkeletonPulse())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Caricamento")
    }
}
