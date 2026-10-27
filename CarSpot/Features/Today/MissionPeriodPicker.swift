import SwiftUI

/// Selettore a 4 segmenti (Oggi, Settimana, Mese, Comuni) con pallini numerati:
/// rosso = da riscattare, verde = nuove (il rosso vince).
struct MissionPeriodPicker: View {
    @Binding var selection: MissionPeriodKind
    let segments: [MissionSegment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pill

    // Pallino numerato: misure fisse, il testo non cresce oltre "large".
    private let badgeMinSize: CGFloat = 13
    private let badgeMaxCount = 9

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
                    // Il pallino parte dall'angolo alto a destra dell'etichetta e cresce verso destra.
                    .overlay(alignment: .topTrailing) {
                        if let segment {
                            badge(for: segment)
                                .alignmentGuide(.trailing) { $0[.leading] }
                                .alignmentGuide(.top) { $0.height / 2 }
                        }
                    }
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

    /// Pallino piccolo con numero; nessuno se non c'è nulla da segnalare.
    @ViewBuilder private func badge(for segment: MissionSegment) -> some View {
        let claimable = segment.claimableCount
        let fresh = segment.newCount
        if claimable > 0 {
            dot(countText(claimable), fill: CSColor.danger, text: CSColor.inkInverse)
        } else if fresh > 0 {
            dot(countText(fresh), fill: CSColor.success, text: CSColor.inkInverse)
        }
    }

    private func countText(_ count: Int) -> String {
        count > badgeMaxCount ? "\(badgeMaxCount)+" : "\(count)"
    }

    private func dot(_ value: String, fill: Color, text: Color) -> some View {
        Text(value)
            .font(CSFont.micro).monospacedDigit()
            .dynamicTypeSize(...DynamicTypeSize.large)
            .foregroundStyle(text)
            .padding(.horizontal, CSSpace.xxs)
            .frame(minWidth: badgeMinSize, minHeight: badgeMinSize)
            .background(fill, in: Capsule())
            .accessibilityHidden(true)
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
