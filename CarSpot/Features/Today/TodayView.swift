import SwiftUI

struct TodayView: View {
    @State private var challenges = DailyChallenge.sample
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.lg) {
                SheetHeader(title: "Oggi")

                greeting
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                levelCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)

                VStack(alignment: .leading, spacing: CSSpace.md) {
                    Text("Obiettivi del giorno").eyebrow().padding(.horizontal, 4)
                    ForEach(Array(challenges.enumerated()), id: \.element.id) { index, challenge in
                        ChallengeRow(challenge: challenge)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 30)
                            .animation(.spring(response: 0.6, dampingFraction: 0.85)
                                .delay(0.15 + Double(index) * 0.08), value: appeared)
                    }
                }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { appeared = true }
        }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month()).capitalized)
                    .eyebrow(CSColor.accent)
                Text("Buona caccia, Andrea")
                    .font(CSFont.title(22))
                    .foregroundStyle(CSColor.ink)
            }
            Spacer()
            streakPill
        }
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            Text("🔥").font(.system(size: 18))
            VStack(alignment: .leading, spacing: -2) {
                Text("7").font(CSFont.numeric(18)).foregroundStyle(CSColor.ink)
                Text("giorni").font(.system(size: 9, weight: .bold)).foregroundStyle(CSColor.inkTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.sm))
    }

    private var levelCard: some View {
        GlassPanel(tint: CSColor.accent) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Livello 12").font(CSFont.display(24)).foregroundStyle(CSColor.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 12, weight: .black))
                        Text("2.450").font(CSFont.numeric(16))
                    }
                    .foregroundStyle(CSColor.accentWarm)
                }
                StatBar(label: "verso il livello 13", value: 64, tint: CSColor.accent)
                Text("340 PE al prossimo livello")
                    .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
            }
        }
    }
}

/// One daily objective with progress ring and reward.
struct ChallengeRow: View {
    let challenge: DailyChallenge

    var body: some View {
        GlassPanel(cornerRadius: CSRadius.md, padding: CSSpace.md) {
            HStack(spacing: CSSpace.md) {
                ZStack {
                    Circle().fill(.white.opacity(0.06)).frame(width: 46, height: 46)
                    Image(systemName: challenge.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(challenge.done ? CSColor.accent : CSColor.ink)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(challenge.title)
                        .font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        ForEach(0..<challenge.goal, id: \.self) { i in
                            Capsule()
                                .fill(i < challenge.progress ? CSColor.accent : Color.white.opacity(0.12))
                                .frame(height: 5)
                        }
                    }
                }

                VStack(spacing: 2) {
                    if challenge.done {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22)).foregroundStyle(CSColor.accent)
                    } else {
                        Text("+\(challenge.reward)").font(CSFont.numeric(15))
                            .foregroundStyle(CSColor.accentWarm)
                        Text("PE").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CSColor.inkTertiary)
                    }
                }
                .frame(width: 44)
            }
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); TodayView() }.preferredColorScheme(.dark)
}
