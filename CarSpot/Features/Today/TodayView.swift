import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync: SyncService?
    @Query private var cards: [StoredCard]
    @Query private var profiles: [PlayerProfile]
    @Environment(ProfileAccount.self) private var account: ProfileAccount?

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

                goalsSection
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    /// I tre obiettivi sono un solo gruppo di righe, non tre card separate.
    private var goalsSection: some View {
        let list = challenges
        let doneCount = list.filter(\.done).count
        return VStack(alignment: .leading, spacing: CSSpace.sm) {
            Text("Obiettivi del giorno · \(doneCount) di \(list.count)")
                .eyebrow()
                .padding(.horizontal, CSSpace.xxs)
            Surface(.group, padding: nil) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, challenge in
                        if index > 0 { SurfaceDivider(inset: CSSpace.md) }
                        ChallengeRow(challenge: challenge) { claim(challenge) }
                    }
                }
            }
        }
    }

    private func claim(_ challenge: DailyChallengeVM) {
        if PlayerStore.claim(challenge, in: context) {
            AppServices.analytics.track(.challengeClaimed(id: challenge.id, reward: challenge.reward))
            let key = "\(PlayerProfile.dayKey())|\(challenge.id)"
            Task { await sync?.didClaim(key: key) }
        }
    }

    /// Data lunga con la sola iniziale maiuscola ("Mercoledì 21 ottobre" / "Wednesday, October 21"),
    /// nella lingua in cui gira l'app.
    private var dateText: String {
        let text = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)
            .locale(.app))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var greetingText: String {
        guard let name = account?.username, !name.isEmpty else { return String(localized: "Buona caccia") }
        return String(localized: "Buona caccia, @\(name)")
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
            Spacer(minLength: 0)
        }
    }

    private var dayUnitSingular: LocalizedStringKey { "giorno" }
    private var dayUnitPlural: LocalizedStringKey { "giorni" }

    /// Blocco eroe: livello, progresso verso il prossimo, serie e carte.
    private var levelCard: some View {
        let xp = profile?.xp ?? 0
        let p = LevelSystem.progress(forXP: xp)
        let percent = Int(p.fraction * 100)
        let streak = profile?.streak ?? 0
        // Le ripetizioni non sono in collezione: non contano nel totale.
        let cardCount = cards.filter { !$0.isRepeat }.count
        return Surface(.hero) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: CSSpace.xxs) {
                        Text("Livello").eyebrow()
                        Text("\(p.level)")
                            .font(CSFont.display(34)).monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                    }
                    Spacer(minLength: CSSpace.md)
                    Text("\(p.into) / \(p.needed) PE")
                        .font(CSFont.numeric(17)).monospacedDigit()
                        .foregroundStyle(CSColor.accentWarm)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)

                StatBar(label: "Verso il livello \(p.level + 1)",
                        value: percent, tint: CSColor.accent,
                        valueText: "\(percent)%")

                HStack {
                    HStack(spacing: CSSpace.xs) {
                        Image(systemName: "flame.fill")
                            .font(CSFont.caption(13))
                            .foregroundStyle(CSColor.accentWarm)
                            .accessibilityHidden(true)
                        Text("\(streak)").font(CSFont.numeric(15)).monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                        // Solo l'unità (il numero è accanto): due chiavi, il plurale del catalogo
                        // richiede il numero nella stringa.
                        Text(streak == 1 ? dayUnitSingular : dayUnitPlural)
                            .font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Serie di \(streak) giorni")
                    Spacer(minLength: CSSpace.md)
                    HStack(spacing: CSSpace.xs) {
                        Text("\(cardCount)").font(CSFont.numeric(15)).monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                        Text("Carte").font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// One daily objective with progress and a claim button when completed.
struct ChallengeRow: View {
    let challenge: DailyChallengeVM
    var onClaim: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { challenge.done ? CSColor.success : CSColor.accent }

    var body: some View {
        HStack(spacing: CSSpace.md) {
            ZStack {
                Circle().fill(CSColor.nested).frame(width: 40, height: 40)
                Image(systemName: challenge.done ? "checkmark" : challenge.icon)
                    .font(CSFont.title(16))
                    .foregroundStyle(challenge.done ? CSColor.success : CSColor.inkSecondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CSSpace.xs) {
                Text(challenge.title)
                    .font(CSFont.body(15))
                    .foregroundStyle(challenge.claimed ? CSColor.inkSecondary : CSColor.ink)
                    .strikethrough(challenge.claimed, color: CSColor.inkTertiary)
                    .lineLimit(2)
                if !challenge.claimed {
                    HStack(spacing: CSSpace.xs) {
                        ForEach(0..<challenge.goal, id: \.self) { i in
                            Capsule()
                                .fill(i < challenge.progress ? tint : CSColor.nested)
                                .frame(height: 5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progresso")
                    .accessibilityValue("\(challenge.progress) di \(challenge.goal)")
                }
            }

            trailing
                .frame(minWidth: 64)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.95)))
        }
        .padding(CSSpace.md)
        .animation(reduceMotion ? nil : .smooth, value: challenge.claimed)
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.success, trigger: challenge.claimed) { old, new in !old && new }
    }

    @ViewBuilder private var trailing: some View {
        if challenge.claimed {
            Text("Fatto")
                .font(CSFont.caption(13))
                .foregroundStyle(CSColor.success)
                .accessibilityLabel("Riscattato")
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
