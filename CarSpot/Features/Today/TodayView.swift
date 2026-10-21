import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync: SyncService?
    @Query private var cards: [StoredCard]
    @Query private var profiles: [PlayerProfile]
    @Environment(ProfileAccount.self) private var account: ProfileAccount?
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
                    Text("Obiettivi del giorno").eyebrow().padding(.horizontal, CSSpace.xxs)
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
            let key = "\(PlayerProfile.dayKey())|\(challenge.id)"
            Task { await sync?.didClaim(key: key) }
        }
    }

    /// Data lunga con la sola iniziale maiuscola ("Mercoledì 21 ottobre").
    private var dateText: String {
        let text = Date.now.formatted(.dateTime.weekday(.wide).day().month())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var greetingText: String {
        guard let name = account?.username, !name.isEmpty else { return "Buona caccia" }
        return "Buona caccia, @\(name)"
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                Text(dateText)
                    .eyebrow(CSColor.accent)
                Text(greetingText)
                    .font(CSFont.title(22))
                    .foregroundStyle(CSColor.ink)
            }
            Spacer()
            streakPill
        }
    }

    private var streakPill: some View {
        let streak = profile?.streak ?? 0
        return HStack(spacing: CSSpace.xs) {
            Text("🔥").font(CSFont.body(18))
            VStack(alignment: .leading, spacing: -2) {
                Text("\(streak)").font(CSFont.numeric(18)).foregroundStyle(CSColor.ink)
                Text(streak == 1 ? "giorno" : "giorni")
                    .font(CSFont.micro).foregroundStyle(CSColor.inkTertiary)
            }
        }
        .padding(.horizontal, CSSpace.md).padding(.vertical, CSSpace.sm)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.sm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Serie di \(streak) \(streak == 1 ? "giorno" : "giorni")")
    }

    private var levelCard: some View {
        let xp = profile?.xp ?? 0
        let p = LevelSystem.progress(forXP: xp)
        let percent = Int(p.fraction * 100)
        return GlassPanel(tint: CSColor.accent) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Livello \(p.level)").font(CSFont.display(24)).foregroundStyle(CSColor.ink)
                    Spacer()
                    HStack(spacing: CSSpace.xxs) {
                        Image(systemName: "bolt.fill").font(CSFont.numeric(12))
                        Text("\(xp)").font(CSFont.numeric(16)).contentTransition(.numericText())
                    }
                    .foregroundStyle(CSColor.accentWarm)
                }
                StatBar(label: "verso il livello \(p.level + 1)",
                        value: percent, tint: CSColor.accent, animate: false,
                        valueText: "\(percent)%")
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassPanel(cornerRadius: CSRadius.md, padding: CSSpace.md) {
            HStack(spacing: CSSpace.md) {
                ZStack {
                    Circle().fill(.white.opacity(0.06)).frame(width: 46, height: 46)
                    Image(systemName: challenge.icon)
                        .font(CSFont.title(18))
                        .foregroundStyle(challenge.done ? CSColor.accent : CSColor.ink)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CSSpace.xs) {
                    Text(challenge.title)
                        .font(CSFont.body(15)).foregroundStyle(CSColor.ink)
                        .lineLimit(2)
                    HStack(spacing: CSSpace.xs) {
                        ForEach(0..<challenge.goal, id: \.self) { i in
                            Capsule()
                                .fill(i < challenge.progress ? CSColor.accent : Color.white.opacity(0.12))
                                .frame(height: 5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progresso")
                    .accessibilityValue("\(challenge.progress) di \(challenge.goal)")
                }

                trailing
                    .frame(minWidth: 64)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.95)))
            }
            .animation(reduceMotion ? nil : .smooth, value: challenge.claimed)
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.success, trigger: challenge.claimed) { old, new in !old && new }
    }

    @ViewBuilder private var trailing: some View {
        if challenge.claimed {
            VStack(spacing: CSSpace.xxs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(CSFont.title(22)).foregroundStyle(CSColor.accent)
                Text("Riscattato").font(CSFont.micro)
                    .foregroundStyle(CSColor.inkTertiary)
            }
            .accessibilityElement(children: .combine)
        } else if challenge.done {
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
            .accessibilityLabel("Riscatta \(challenge.title), \(challenge.reward) punti esperienza")
        } else {
            VStack(spacing: CSSpace.xxs) {
                Text("+\(challenge.reward)").font(CSFont.numeric(15))
                    .foregroundStyle(CSColor.accentWarm)
                Text("PE").font(CSFont.micro)
                    .foregroundStyle(CSColor.inkTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ricompensa \(challenge.reward) punti esperienza")
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); TodayView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
