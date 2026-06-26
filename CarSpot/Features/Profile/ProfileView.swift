import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: CSSpace.lg) {
                header
                profileHeader
                myCarCard
                sightingsCard
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Profilo")
                .font(CSFont.display(34))
                .foregroundStyle(CSColor.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: CSSpace.sm) {
            UserAvatar(size: 88)
            Text("Andrea").font(CSFont.display(26)).foregroundStyle(CSColor.ink)
            Text("Cacciatore Livello 12").eyebrow(CSColor.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CSSpace.xs)
    }

    private var myCarCard: some View {
        GlassPanel(tint: CSColor.accent) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                HStack {
                    Text("La mia auto").eyebrow(CSColor.accent)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(CSColor.accent)
                }
                HStack(spacing: CSSpace.md) {
                    Image(systemName: "car.side.fill").font(.system(size: 34))
                        .foregroundStyle(Rarity.rara.linearGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Volkswagen Golf GTI").font(CSFont.title(17)).foregroundStyle(CSColor.ink)
                        Text("Avvistata 23 volte questo mese")
                            .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                    }
                    Spacer()
                }
                HStack {
                    Label("+340 PE passivi", systemImage: "bolt.fill")
                        .font(CSFont.caption()).foregroundStyle(CSColor.accentWarm)
                    Spacer()
                }
            }
        }
    }

    private var sightingsCard: some View {
        GlassPanel(cornerRadius: CSRadius.md) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                Text("Ultimi avvistamenti").eyebrow()
                sightingRow("La tua auto è stata avvistata in Centro", "2 ore fa", "❤️")
                Divider().overlay(CSColor.hairline)
                sightingRow("Reazione ricevuta: \"Che fiamma!\"", "ieri", "🔥")
                Divider().overlay(CSColor.hairline)
                sightingRow("Avvistata al Lungomare", "2 giorni fa", "👀")
            }
        }
    }

    private func sightingRow(_ text: String, _ time: String, _ emoji: String) -> some View {
        HStack(spacing: CSSpace.md) {
            Text(emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 1) {
                Text(text).font(CSFont.body(14)).foregroundStyle(CSColor.ink).lineLimit(1)
                Text(time).font(CSFont.caption(11)).foregroundStyle(CSColor.inkTertiary)
            }
            Spacer()
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); ProfileView() }.preferredColorScheme(.dark)
}
