import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [StoredCard]
    @Query private var profiles: [PlayerProfile]
    @State private var appeared = false

    private var profile: PlayerProfile? { profiles.first }

    private var challenges: [DailyChallengeVM] {
        ChallengeEngine.today(cards: cards, claimed: profile?.claimedChallenges ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.lg) {
                SheetHeader(title: "Oggi")

                greeting

                levelCard

                VStack(alignment: .leading, spacing: CSSpace.md) {
                    Text("Obiettivi del giorno").eyebrow().padding(.horizontal, 4)
                    ForEach(challenges) { challenge in
                        ChallengeRow(challenge: challenge) { claim(challenge) }
                    }
                }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: appeared)
        }
        .scrollIndicators(.hidden)
        .onAppear { appeared = true }
    }

    private func claim(_ challenge: DailyChallengeVM) {
        if PlayerStore.claim(challenge, in: context) {
            AppServices.analytics.track(.challengeClaimed(id: challenge.id))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                Text("\(profile?.streak ?? 1)").font(CSFont.numeric(18)).foregroundStyle(CSColor.ink)
                Text("giorni").font(.system(size: 9, weight: .bold)).foregroundStyle(CSColor.inkTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.sm))
    }

    private var levelCard: some View {
        let xp = profile?.xp ?? 0
        let p = LevelSystem.progress(forXP: xp)
        return GlassPanel(tint: CSColor.accent) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Livello \(p.level)").font(CSFont.display(24)).foregroundStyle(CSColor.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 12, weight: .black))
                        Text("\(xp)").font(CSFont.numeric(16)).contentTransition(.numericText())
                    }
                    .foregroundStyle(CSColor.accentWarm)
                }
                StatBar(label: "verso il livello \(p.level + 1)",
                        value: Int(p.fraction * 100), tint: CSColor.accent, animate: false)
                Text("\(max(0, p.needed - p.into)) PE al prossimo livello")
                    .font(CSFont.caption()).foregroundStyle(CSColor.inkSecondary)
            }
        }
    }
}

/// One daily objective with progress and a claim button when completed.
struct ChallengeRow: View {
    let challenge: DailyChallengeVM
    var onClaim: () -> Void

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

                trailing
                    .frame(width: 64)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if challenge.claimed {
            VStack(spacing: 2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22)).foregroundStyle(CSColor.accent)
                Text("Riscattato").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CSColor.inkTertiary)
            }
        } else if challenge.done {
            Button(action: onClaim) {
                Text("Riscatta")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Capsule().fill(CSColor.accent))
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 2) {
                Text("+\(challenge.reward)").font(CSFont.numeric(15))
                    .foregroundStyle(CSColor.accentWarm)
                Text("PE").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CSColor.inkTertiary)
            }
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); TodayView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
