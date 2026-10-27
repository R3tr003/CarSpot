import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync: SyncService?
    @Query private var cards: [StoredCard]
    @Query private var profiles: [PlayerProfile]
    @Environment(ProfileAccount.self) private var account: ProfileAccount?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profile: PlayerProfile? { profiles.first }

    /// Selezione ricordata finché la schermata esiste.
    @State private var selection: MissionPeriodKind = .day
    /// Missioni comuni da disco, solo se manca il `SyncService` (ospite / offline).
    @State private var cachedCommunity: [CommunityMission] = []
    /// Cresce a ogni riscatto riuscito: fa partire l'aptica di successo (una sola, qui).
    @State private var claimTicks = 0

    /// Tabellone e serie in cache: si ricalcolano solo quando cambia `boardKey`, non a ogni minuto.
    @State private var board: [MissionSegment] = []
    @State private var streakState = StreakState(count: 0, status: .pending)
    /// Inizio del giorno corrente: lo aggiorna la timeline, così i periodi girano a mezzanotte.
    @State private var dayKey = Calendar.missions.startOfDay(for: .now)

    /// Tutto ciò che può cambiare il tabellone o la serie.
    private struct BoardKey: Hashable {
        let cardCount: Int
        let latestCapture: Date?
        let claimed: [String]
        let seen: [String]
        let communityIDs: [String]
        let day: Date
    }

    private var boardKey: BoardKey {
        BoardKey(
            cardCount: cards.count,
            latestCapture: cards.map(\.capturedAt).max(),
            claimed: profile?.claimedMissions ?? [],
            seen: profile?.seenMissions ?? [],
            communityIDs: (sync?.communityMissions ?? cachedCommunity).map(\.id),
            day: dayKey)
    }

    private func recomputeBoard() {
        let now = Date.now
        board = MissionBoard.build(
            cards: cards.map(MissionCard.init),
            ownerId: profile?.ownerId ?? "",
            claimed: Set(profile?.claimedMissions ?? []),
            seen: Set(profile?.seenMissions ?? []),
            community: sync?.communityMissions ?? cachedCommunity,
            region: Locale.current.region?.identifier,
            now: now,
            calendar: .missions
        )
        streakState = StreakCalculator.state(
            captures: cards.map { StreakCapture(capturedAt: $0.capturedAt, rarity: $0.rarity, isRepeat: $0.isRepeat) },
            now: now, calendar: .missions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CSSpace.lg) {
                SheetHeader(title: "Oggi")

                greeting

                levelCard

                // Ogni minuto rilegge l'orario: solo per "finisce tra…" e per il cambio di giorno.
                TimelineView(.everyMinute) { timeline in
                    missionsSection(now: timeline.date)
                        .onChange(of: Calendar.missions.startOfDay(for: timeline.date)) { _, day in
                            dayKey = day
                        }
                }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: claimTicks)
        .task { if sync == nil { cachedCommunity = CommunityMissionCache.load() } }
        .onChange(of: boardKey, initial: true) { recomputeBoard() }
        .alert("Riscatto annullato", isPresented: rejectionShown, presenting: sync?.claimRejections.first) { _ in
            Button("OK") { sync?.clearClaimRejections() }
        } message: { rejection in
            Text(rejectionMessage(rejection))
        }
    }

    /// L'avviso resta finché ci sono riscatti annullati; il pulsante li svuota.
    private var rejectionShown: Binding<Bool> {
        Binding(get: { !(sync?.claimRejections.isEmpty ?? true) }, set: { _ in })
    }

    private func rejectionMessage(_ rejection: ClaimRejection) -> String {
        let title = rejection.title
        let reason = rejection.expired
            ? String(localized: "«\(title)»: il riscatto non è arrivato in tempo al server.")
            : String(localized: "«\(title)» non risulta completata sul server.")
        guard rejection.reward > 0 else { return reason }
        return reason + " " + String(localized: "\(rejection.reward) PE tolti.")
    }

    /// Selettore di periodo, poi un solo gruppo di righe (e gli avanzi del periodo prima).
    private func missionsSection(now: Date) -> some View {
        let all = board
        let segment = all.first { $0.kind == selection }
        let currentIDs = segment?.current.map(\.id) ?? []
        return VStack(alignment: .leading, spacing: CSSpace.sm) {
            MissionPeriodPicker(selection: $selection, segments: all)

            // Il cambio di contenuto non deve rimbalzare: anima solo la pillola del selettore.
            VStack(alignment: .leading, spacing: CSSpace.sm) {
                if let segment {
                    if !segment.current.isEmpty {
                        let done = segment.current.filter(\.done).count
                        HStack {
                            Text("\(done) di \(segment.current.count)")
                                .accessibilityLabel("\(done) di \(segment.current.count) completate")
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: CSSpace.md)
                            if let endsAt = segment.endsAt { Text(endsInText(endsAt, now: now)) }
                        }
                        .eyebrow()
                        .padding(.horizontal, CSSpace.xxs)
                        group(segment.current)
                    } else if segment.kind == .community {
                        Surface(.group) {
                            Text("Nessuna missione comune in corso")
                                .font(CSFont.body(15))
                                .foregroundStyle(CSColor.inkSecondary)
                        }
                    }

                    if !segment.leftovers.isEmpty {
                        Text(leftoversTitle(segment))
                            .eyebrow()
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, CSSpace.xxs)
                            .padding(.top, CSSpace.sm)
                        group(segment.leftovers)
                    }
                }
            }
            .animation(nil, value: selection)
        }
        // Aprire un segmento (o l'arrivo di nuove missioni) spegne i suoi pallini verdi.
        .onChange(of: currentIDs, initial: true) {
            PlayerStore.markSeen(currentIDs, in: context)
        }
    }

    private func group(_ list: [MissionStatus]) -> some View {
        Surface(.group, padding: nil) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { SurfaceDivider(inset: CSSpace.md) }
                    MissionRow(status: status) { claim(status) }
                }
            }
        }
    }

    /// "finisce tra 6 h" sotto le 24 ore, altrimenti in giorni.
    private func endsInText(_ end: Date, now: Date) -> LocalizedStringKey {
        let hours = max(1, Int((end.timeIntervalSince(now) / 3600).rounded(.up)))
        if hours < 24 { return "finisce tra \(hours) h" }
        let days = Int((Double(hours) / 24).rounded(.up))
        return "finisce tra \(days) g"
    }

    /// "Settimana scorsa · riscatta entro martedì": l'ultimo giorno utile, il più vicino.
    private func leftoversTitle(_ segment: MissionSegment) -> String {
        let label: String
        switch segment.kind {
        case .day: label = String(localized: "Ieri")
        case .week: label = String(localized: "Settimana scorsa")
        case .month: label = String(localized: "Mese scorso")
        case .community: label = String(localized: "Concluse")
        }
        // `claimDeadline` è esclusiva: l'ultimo giorno utile è quello prima.
        guard let deadline = segment.leftovers.map(\.mission.period.claimDeadline).min() else { return label }
        let day = Calendar.missions.date(byAdding: .day, value: -1, to: deadline) ?? deadline
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(.app))
        return String(localized: "\(label) · riscatta entro \(weekday)")
    }

    private func claim(_ status: MissionStatus) {
        // Le righe avanzate sfumano invece di sparire di colpo.
        let claimed = withAnimation(reduceMotion ? nil : .smooth) {
            PlayerStore.claim(status, in: context)
        }
        guard claimed else { return }
        claimTicks += 1
        let mission = status.mission
        AppServices.analytics.track(.challengeClaimed(
            id: "\(mission.period.kind.rawValue)|\(mission.missionId)", reward: mission.reward))
        let payload = MissionClaimPayload(mission)
        Task { await sync?.didClaimMission(payload) }
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
        let streak = streakState.count
        let atRisk = streakState.status == .atRisk
        let lost = streakState.status == .lost
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
                }
                .accessibilityElement(children: .combine)

                StatBar(label: "Verso il livello \(p.level + 1)",
                        value: percent, tint: CSColor.accent,
                        valueText: "\(percent)%")

                HStack {
                    HStack(spacing: CSSpace.xs) {
                        Image(systemName: "flame.fill")
                            .font(CSFont.caption(13))
                            .foregroundStyle(lost ? CSColor.inkTertiary : CSColor.accentWarm)
                            .accessibilityHidden(true)
                        Text("\(streak)").font(CSFont.numeric(15)).monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                        // Solo l'unità (il numero è accanto): due chiavi, il plurale del catalogo
                        // richiede il numero nella stringa.
                        Text(streak == 1 ? dayUnitSingular : dayUnitPlural)
                            .font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                        if atRisk {
                            Text("· in pericolo")
                                .font(CSFont.caption(13)).foregroundStyle(CSColor.accentWarm)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(atRisk ? "Serie di \(streak) giorni, in pericolo" : "Serie di \(streak) giorni")
                    Spacer(minLength: CSSpace.md)
                    HStack(spacing: CSSpace.xs) {
                        Text("\(cardCount)").font(CSFont.numeric(15)).monospacedDigit()
                            .foregroundStyle(CSColor.ink)
                        Text("Carte").font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if atRisk {
                    Text("Ieri non hai catturato. Prendi una Rara o superiore entro mezzanotte per salvare la serie.")
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CSSpace.sm)
                        .background(CSColor.nested, in: RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous))
                }
            }
        }
    }
}

#Preview {
    ZStack { AsphaltBackground(); TodayView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
