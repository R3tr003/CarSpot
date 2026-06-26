import SwiftUI

private struct Neighborhood: Identifiable {
    let id = UUID()
    var name: String
    var supervisor: String
    var uniqueSpots: Int
    var youHold: Bool
}

struct TerritoryView: View {
    private let zones: [Neighborhood] = [
        .init(name: "Centro Storico", supervisor: "Tu", uniqueSpots: 42, youHold: true),
        .init(name: "Lungomare", supervisor: "marco_rs", uniqueSpots: 38, youHold: false),
        .init(name: "Quartiere Nord", supervisor: "Tu", uniqueSpots: 27, youHold: true),
        .init(name: "Collina", supervisor: "giulia.v", uniqueSpots: 19, youHold: false),
        .init(name: "Stazione", supervisor: "—", uniqueSpots: 8, youHold: false)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.lg) {
                SheetHeader(title: "Mappa")
                summaryCard
                Text("Quartieri").eyebrow().padding(.horizontal, 4)
                ForEach(zones) { zone in zoneRow(zone) }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    private var summaryCard: some View {
        GlassPanel(tint: CSColor.accent) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Controlli 2 quartieri").font(CSFont.title(18)).foregroundStyle(CSColor.ink)
                    Text("+45 risorse al giorno").font(CSFont.caption()).foregroundStyle(CSColor.accentWarm)
                }
                Spacer()
                Image(systemName: "crown.fill").font(.system(size: 28)).foregroundStyle(CSColor.accent)
            }
        }
    }

    private func zoneRow(_ zone: Neighborhood) -> some View {
        GlassPanel(cornerRadius: CSRadius.md, padding: CSSpace.md) {
            HStack(spacing: CSSpace.md) {
                ZStack {
                    Circle().fill(zone.youHold ? CSColor.accent.opacity(0.2) : .white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: zone.youHold ? "crown.fill" : "flag.fill")
                        .foregroundStyle(zone.youHold ? CSColor.accent : CSColor.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.name).font(CSFont.body(16)).foregroundStyle(CSColor.ink)
                    Text("Supervisore: \(zone.supervisor)")
                        .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(zone.uniqueSpots)").font(CSFont.numeric(18)).foregroundStyle(CSColor.ink)
                    Text("uniche").font(.system(size: 9, weight: .bold)).foregroundStyle(CSColor.inkTertiary)
                }
            }
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); TerritoryView() }.preferredColorScheme(.dark)
}
