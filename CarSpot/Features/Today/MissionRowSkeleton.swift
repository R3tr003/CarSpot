import SwiftUI

/// Riga di missione in caricamento: stessa geometria di `MissionRow`.
/// Statica: la pulsazione la dà `.skeletonLoading()` sul gruppo che la contiene.
struct MissionRowSkeleton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Cerchio dell'icona: segue la dimensione del testo, come in `MissionRow`.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CSSpace.sm) {
                    HStack(alignment: .top, spacing: CSSpace.md) {
                        icon
                        textColumn
                    }
                    reward
                }
            } else {
                HStack(spacing: CSSpace.md) {
                    icon
                    textColumn
                    reward
                }
            }
        }
        .padding(CSSpace.md)
    }

    private var icon: some View {
        Circle().fill(CSColor.nested)
            .frame(width: iconSize, height: iconSize)
    }

    private var textColumn: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: CSSpace.xs) {
                SkeletonLine(width: geo.size.width * 0.6, height: 12)
                SkeletonLine(height: 5)
            }
        }
        // Altezza di titolo + barra: il GeometryReader non ne ha una propria.
        .frame(height: 12 + CSSpace.xs + 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reward: some View {
        SkeletonBlock(cornerRadius: 6)
            .frame(width: 40, height: 28)
            .frame(minWidth: 64)
    }
}

#Preview {
    Surface(.group, padding: nil) {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { SurfaceDivider(inset: CSSpace.md) }
                MissionRowSkeleton()
            }
        }
    }
    .skeletonLoading()
    .padding(CSSpace.lg)
    .background(CSColor.panel)
    .preferredColorScheme(.dark)
}
