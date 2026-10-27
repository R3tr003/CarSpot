import SwiftUI

/// Una missione con progresso e, se completata, il pulsante per riscattarla.
struct MissionRow: View {
    let status: MissionStatus
    var onClaim: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Cerchio dell'icona: segue la dimensione del testo.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    private var mission: Mission { status.mission }
    private var tint: Color { status.done ? CSColor.success : CSColor.accent }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Testo molto grande: il pulsante va sotto, la colonna usa tutta la larghezza.
                VStack(alignment: .leading, spacing: CSSpace.sm) {
                    HStack(alignment: .top, spacing: CSSpace.md) {
                        icon
                        textColumn
                    }
                    trailingView
                }
            } else {
                HStack(spacing: CSSpace.md) {
                    icon
                    textColumn
                    trailingView
                }
            }
        }
        .padding(CSSpace.md)
        .animation(reduceMotion ? nil : .smooth, value: status.claimed)
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        ZStack {
            Circle().fill(CSColor.nested).frame(width: iconSize, height: iconSize)
            Image(systemName: status.done ? "checkmark" : mission.icon)
                .font(CSFont.title(16))
                .foregroundStyle(status.done ? CSColor.success : CSColor.inkSecondary)
        }
        .accessibilityHidden(true)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: CSSpace.xs) {
            titleLine
            if !status.claimed { progress }
            detailLine
        }
        // Occupa tutto lo spazio: icona e "Fatto" restano allineati riga per riga.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailingView: some View {
        trailing
            .frame(minWidth: 64)
    }

    // MARK: - Titolo

    private var titleLine: some View {
        Text(mission.title)
            .font(CSFont.body(15))
            .foregroundStyle(status.claimed ? CSColor.inkSecondary : CSColor.ink)
            .strikethrough(status.claimed, color: CSColor.inkTertiary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
    }

    /// Ambito di una missione comune (Mondo / Europa / Paese), nella riga dei dettagli.
    @ViewBuilder private var scopeChip: some View {
        if case .community(let scope) = mission.source {
            Text(Self.scopeName(scope))
                .font(CSFont.micro)
                .foregroundStyle(CSColor.inkTertiary)
                .lineLimit(1)
                .padding(.horizontal, CSSpace.xs)
                .padding(.vertical, CSSpace.xxs)
                .overlay(Capsule().strokeBorder(CSColor.hairline, lineWidth: 1))
        }
    }

    // MARK: - Progresso

    /// Fino a 5 passi: capsule a segmenti; oltre, barra continua e "7 di 12".
    @ViewBuilder private var progress: some View {
        if mission.goal <= 5 {
            HStack(spacing: CSSpace.xs) {
                ForEach(0..<max(0, mission.goal), id: \.self) { i in
                    Capsule()
                        .fill(i < status.progress ? tint : CSColor.nested)
                        .frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progresso")
            .accessibilityValue("\(status.progress) di \(mission.goal)")
        } else {
            HStack(spacing: CSSpace.sm) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CSColor.nested)
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 5)
                Text("\(status.progress) di \(mission.goal)")
                    .font(CSFont.caption(13)).monospacedDigit()
                    .foregroundStyle(CSColor.inkSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progresso")
            .accessibilityValue("\(status.progress) di \(mission.goal)")
        }
    }

    private var fraction: CGFloat {
        guard mission.goal > 0 else { return 0 }
        return min(1, CGFloat(status.progress) / CGFloat(mission.goal))
    }

    // MARK: - Dettagli (badge in palio, scadenza delle comuni)

    @ViewBuilder private var detailLine: some View {
        let isCommunity = mission.source != .personal
        if mission.badgeId != nil || isCommunity {
            // Testo molto grande: gli elementi vanno uno sotto l'altro.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: CSSpace.xs))
                : AnyLayout(HStackLayout(spacing: CSSpace.sm))
            layout {
                scopeChip
                if mission.badgeId != nil {
                    HStack(spacing: CSSpace.xxs) {
                        Image(systemName: "rosette")
                            .accessibilityHidden(true)
                        Text(status.claimed ? "Badge ottenuto" : "Badge")
                    }
                    .foregroundStyle(status.claimed ? CSColor.success : CSColor.accentWarm)
                }
                if isCommunity && !status.claimed {
                    Text(untilText).foregroundStyle(CSColor.inkSecondary)
                        .lineLimit(1)
                }
            }
            .font(CSFont.micro)
        }
    }

    /// "fino al 30 nov": `end` è esclusivo, l'ultimo giorno è quello prima.
    private var untilText: String {
        let last = Calendar.missions.date(byAdding: .day, value: -1, to: mission.period.end) ?? mission.period.end
        let date = last.formatted(.dateTime.day().month(.abbreviated).locale(.app))
        return String(localized: "fino al \(date)")
    }

    /// Mondo / Europa / nome del Paese, in maiuscolo.
    private static func scopeName(_ scope: String) -> String {
        switch scope.uppercased() {
        case "WORLD": String(localized: "Mondo").uppercased()
        case "EUROPE": String(localized: "Europa").uppercased()
        default: (Locale.app.localizedString(forRegionCode: scope) ?? scope).uppercased()
        }
    }

    // MARK: - Destra

    @ViewBuilder private var trailing: some View {
        if status.claimed {
            Text("Fatto")
                .font(CSFont.caption(13))
                .foregroundStyle(CSColor.success)
                .accessibilityLabel("Riscattata")
        } else if status.claimable {
            Button(action: onClaim) {
                Text("Riscatta")
                    .font(CSFont.caption(13))
                    .foregroundStyle(CSColor.inkInverse)
                    .padding(.horizontal, CSSpace.sm)
                    .frame(minWidth: 64, minHeight: CSSize.minTap)
                    .background(Capsule().fill(CSColor.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(CSPressStyle())
            .accessibilityLabel(claimLabel)
        } else {
            VStack(spacing: CSSpace.xxs) {
                Text("+\(mission.reward)").font(CSFont.numeric(15))
                    .foregroundStyle(CSColor.accentWarm)
                Text("PE").font(CSFont.micro)
                    .foregroundStyle(CSColor.inkTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ricompensa \(mission.reward) punti esperienza")
        }
    }

    private var claimLabel: String {
        mission.badgeId != nil
            ? String(localized: "Riscatta \(mission.title), \(mission.reward) punti esperienza e un badge")
            : String(localized: "Riscatta \(mission.title), \(mission.reward) punti esperienza")
    }
}
