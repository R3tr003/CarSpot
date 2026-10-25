import SwiftUI

private struct Neighborhood: Identifiable {
    let id = UUID()
    var name: LocalizedStringResource
    var supervisor: String?
    var uniqueSpots: Int
    var youHold: Bool
}

struct TerritoryView: View {
    private let zones: [Neighborhood] = [
        .init(name: "Centro Storico", supervisor: String(localized: "Tu"), uniqueSpots: 42, youHold: true),
        .init(name: "Lungomare", supervisor: "marco_rs", uniqueSpots: 38, youHold: false),
        .init(name: "Quartiere Nord", supervisor: String(localized: "Tu"), uniqueSpots: 27, youHold: true),
        .init(name: "Collina", supervisor: "giulia.v", uniqueSpots: 19, youHold: false),
        .init(name: "Stazione", supervisor: nil, uniqueSpots: 8, youHold: false)
    ]

    private var heldCount: Int { zones.filter(\.youHold).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.lg) {
                SheetHeader(title: "Mappa")
                // I quartieri sono dati di esempio: non farli passare per reali.
                Text("Anteprima · dati di esempio")
                    .eyebrow(CSColor.accentWarm)
                    .padding(.horizontal, CSSpace.xxs)
                summaryCard
                Text("Quartieri").eyebrow().padding(.horizontal, CSSpace.xxs)
                Surface(.group, padding: nil) {
                    VStack(spacing: 0) {
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            if index > 0 { SurfaceDivider(inset: CSSpace.md) }
                            zoneRow(zone)
                        }
                    }
                }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    private var summaryCard: some View {
        Surface(.hero) {
            HStack {
                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    Text("Controlli \(heldCount) quartieri").font(CSFont.title(18)).foregroundStyle(CSColor.ink)
                    Text("+45 risorse al giorno").font(CSFont.caption()).foregroundStyle(CSColor.accentWarm)
                }
                Spacer()
                Image(systemName: "crown.fill").font(CSFont.display(28)).foregroundStyle(CSColor.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private func zoneRow(_ zone: Neighborhood) -> some View {
        HStack(spacing: CSSpace.md) {
            ZStack {
                Circle().fill(CSColor.nested)
                    .frame(width: 44, height: 44)
                Image(systemName: zone.youHold ? "crown.fill" : "flag.fill")
                    .foregroundStyle(zone.youHold ? CSColor.accent : CSColor.inkSecondary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                Text(zone.name).font(CSFont.body(16)).foregroundStyle(CSColor.ink)
                Text(zone.supervisor.map { String(localized: "Supervisore: \($0)") } ?? String(localized: "Nessun supervisore"))
                    .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(zone.uniqueSpots)").font(CSFont.numeric(18)).foregroundStyle(CSColor.ink)
                Text("uniche").font(CSFont.micro).foregroundStyle(CSColor.inkTertiary)
            }
        }
        .padding(CSSpace.md)
        .accessibilityElement(children: .combine)
        .accessibilityValue(zone.youHold ? Text("Lo controlli tu") : Text(verbatim: ""))
    }
}

#Preview {
    ZStack { AsphaltBackground(); TerritoryView() }.preferredColorScheme(.dark)
}
