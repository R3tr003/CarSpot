import SwiftUI

/// Selettore a 4 segmenti (Oggi, Settimana, Mese, Comuni) con un puntino accanto alla
/// parola: rosso = da riscattare, verde = nuove (il rosso vince). I numeri li legge VoiceOver.
struct MissionPeriodPicker: View {
    @Binding var selection: MissionPeriodKind
    let segments: [MissionSegment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pill

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Testo molto grande: quattro etichette in una riga non ci stanno, griglia 2×2.
                Grid(horizontalSpacing: CSSpace.xxs, verticalSpacing: CSSpace.xxs) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(MissionPeriodKind.allCases.dropFirst(row * 2).prefix(2), id: \.self) { kind in
                                segmentButton(kind)
                            }
                        }
                    }
                }
                .padding(CSSpace.xxs)
                .background(CSColor.group, in: RoundedRectangle(cornerRadius: CSRadius.md, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    ForEach(MissionPeriodKind.allCases, id: \.self) { kind in
                        segmentButton(kind)
                    }
                }
                .padding(CSSpace.xxs)
                .background(CSColor.group, in: Capsule())
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segmentButton(_ kind: MissionPeriodKind) -> some View {
        let segment = segments.first { $0.kind == kind }
        let selected = selection == kind
        return Button {
            if reduceMotion {
                selection = kind
            } else {
                withAnimation(.spring(duration: 0.3, bounce: 0)) { selection = kind }
            }
        } label: {
            ZStack {
                if selected {
                    Capsule()
                        .fill(CSColor.nested)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
                title(for: kind)
                    // Stesso peso da selezionato e no: cambia solo il colore, le larghezze non saltano.
                    .font(CSFont.caption(13))
                    .foregroundStyle(selected ? CSColor.ink : CSColor.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.8)
                    // Affiancato, mai sopra la parola.
                    .statusDot(segment.flatMap(dotColor))
                    .padding(.horizontal, CSSpace.xxs)
            }
            .frame(maxWidth: .infinity, minHeight: CSSize.minTap)
            .contentShape(Capsule())
        }
        .buttonStyle(CSPressStyle())
        .accessibilityLabel(accessibilityLabel(for: kind, segment: segment))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func title(for kind: MissionPeriodKind) -> Text {
        Text(name(for: kind))
    }

    private func name(for kind: MissionPeriodKind) -> String {
        switch kind {
        case .day: String(localized: "Oggi")
        case .week: String(localized: "Settimana")
        case .month: String(localized: "Mese")
        case .community: String(localized: "Comuni")
        }
    }

    /// Colore del puntino; nessuno se non c'è nulla da segnalare.
    private func dotColor(for segment: MissionSegment) -> Color? {
        if segment.claimableCount > 0 { return CSColor.danger }
        if segment.newCount > 0 { return CSColor.success }
        return nil
    }

    private func accessibilityLabel(for kind: MissionPeriodKind, segment: MissionSegment?) -> String {
        let label = name(for: kind)
        guard let segment else { return label }
        if segment.claimableCount > 0 {
            return String(localized: "\(label), \(segment.claimableCount) da riscattare")
        }
        if segment.newCount > 0 {
            return String(localized: "\(label), \(segment.newCount) nuove")
        }
        return label
    }
}
