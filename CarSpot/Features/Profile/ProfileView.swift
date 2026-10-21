import SwiftUI
import SwiftData
import os

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync: SyncService?
    @Environment(ProfileAccount.self) private var account: ProfileAccount?
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \StoredCard.capturedAt, order: .reverse) private var cards: [StoredCard]

    @State private var consent = AppServices.analytics.consent
    @State private var isSigningOut = false
    @State private var showSignOutDialog = false
    /// Elementi non ancora nel cloud trovati al logout (> 0 = chiede conferma).
    @State private var unsyncedCount = 0
    @State private var showUnsyncedAlert = false
    @State private var showSignOutError = false
    private let auth = AppServices.auth

    private var profile: PlayerProfile? { profiles.first }

    /// Nome mostrato: handle dello spotter, o un fallback se non ancora scelto.
    private var displayName: String {
        guard let name = account?.username, !name.isEmpty else { return "Spotter" }
        return "@\(name)"
    }

    var body: some View {
        // Calcolato una volta per render: usato da intestazione e barra livello.
        let progress = LevelSystem.progress(forXP: profile?.xp ?? 0)
        ScrollView {
            VStack(spacing: CSSpace.lg) {
                header
                profileHeader(progress)
                statsRow
                sightingsCard
                privacyCard
                if auth.state != .signedOut { signOutButton }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, CSSpace.xl)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Vuoi uscire?", isPresented: $showSignOutDialog, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { startSignOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le carte già sincronizzate restano nel cloud: le ritrovi al prossimo accesso.")
        }
        .alert("Dati non sincronizzati", isPresented: $showUnsyncedAlert) {
            Button("Esci comunque", role: .destructive) { signOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(unsyncedCount == 1
                 ? "Hai 1 elemento non ancora salvato nel cloud. Se esci ora lo perdi."
                 : "Hai \(unsyncedCount) elementi non ancora salvati nel cloud. Se esci ora li perdi.")
        }
        .alert("Uscita non riuscita", isPresented: $showSignOutError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Non sono riuscito a uscire. Riprova.")
        }
    }

    private var statsRow: some View {
        HStack(spacing: CSSpace.md) {
            statTile(cards.count, "Carte", CSColor.accent)
            statTile(profile?.xp ?? 0, "PE", CSColor.accentWarm, spoken: "Punti esperienza")
            statTile(profile?.currency ?? 0, "Valuta", Rarity.epica.primary)
        }
    }

    private func statTile(_ value: Int, _ label: String, _ tint: Color, spoken: String? = nil) -> some View {
        VStack(spacing: CSSpace.xxs) {
            Text(value, format: .number)
                .font(CSFont.numeric(24))
                .foregroundStyle(CSColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .eyebrow(tint)
                .accessibilityLabel(spoken ?? label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Profilo")
                .font(CSFont.display(34))
                .foregroundStyle(CSColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(CSFont.title(16))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: CSSize.minTap, height: CSSize.minTap)
                    .glassEffect(.regular, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
        }
    }

    private func profileHeader(_ progress: (level: Int, into: Int, needed: Int, fraction: Double)) -> some View {
        VStack(spacing: CSSpace.sm) {
            UserAvatar(size: 88, name: account?.username ?? "")
                .accessibilityHidden(true)
            Text(displayName)
                .font(CSFont.display(26))
                .foregroundStyle(CSColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Cacciatore Livello \(progress.level)").eyebrow(CSColor.accent)
            levelProgress(progress)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CSSpace.xs)
    }

    private func levelProgress(_ progress: (level: Int, into: Int, needed: Int, fraction: Double)) -> some View {
        let hasXP = (profile?.xp ?? 0) > 0
        return VStack(spacing: CSSpace.xs) {
            StatBar(
                label: "Livello \(progress.level)",
                value: Int((progress.fraction * 100).rounded(.down)),
                tint: CSColor.accent,
                animate: false,
                valueText: "\(progress.into) / \(progress.needed) PE"
            )
            Text(hasXP
                 ? "\(progress.needed - progress.into) PE al livello \(progress.level + 1)"
                 : "Fotografa la prima auto per salire di livello")
                .font(CSFont.caption(12))
                .foregroundStyle(CSColor.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, CSSpace.xs)
    }

    private var sightingsCard: some View {
        GlassPanel(cornerRadius: CSRadius.md) {
            VStack(alignment: .leading, spacing: CSSpace.md) {
                Text("Ultimi avvistamenti").eyebrow()
                if cards.isEmpty {
                    Text("Ancora nessun avvistamento. Fotografa la tua prima auto.")
                        .font(CSFont.body(14))
                        .foregroundStyle(CSColor.inkSecondary)
                } else {
                    let recent = Array(cards.prefix(3))
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, card in
                        if index > 0 { Divider().overlay(CSColor.hairline) }
                        sightingRow(card)
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        GlassPanel(cornerRadius: CSRadius.md) {
            VStack(alignment: .leading, spacing: CSSpace.sm) {
                Text("Privacy").eyebrow()
                Toggle(isOn: Binding(
                    get: { consent == .granted },
                    set: { on in
                        let value: AnalyticsConsent = on ? .granted : .denied
                        AppServices.analytics.setConsent(value)
                        consent = value
                    }
                )) {
                    Text("Statistiche anonime")
                        .font(CSFont.body(15))
                        .foregroundStyle(CSColor.ink)
                }
                .tint(CSColor.accent)
                Text("Ci dicono come viene usata l'app. Mai foto, targhe o posizione.")
                    .font(CSFont.caption(12))
                    .foregroundStyle(CSColor.inkSecondary)
            }
        }
    }

    private var signOutButton: some View {
        Button {
            showSignOutDialog = true
        } label: {
            HStack(spacing: CSSpace.xs) {
                if isSigningOut {
                    ProgressView().tint(CSColor.accentWarm)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                Text("Esci")
            }
            .font(CSFont.body(16))
            .foregroundStyle(CSColor.accentWarm)
            .frame(maxWidth: .infinity, minHeight: CSSize.minTap)
            .padding(.vertical, CSSpace.xs)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(CSPressStyle())
        .disabled(isSigningOut)
    }

    /// Dopo la conferma: prima si prova a inviare ciò che è in attesa; se resta qualcosa
    /// si chiede un'ulteriore conferma, altrimenti si esce.
    private func startSignOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        let sync = sync
        Task {
            let left = await sync?.flushPending() ?? 0
            if left > 0 {
                unsyncedCount = left
                showUnsyncedAlert = true
                isSigningOut = false
            } else {
                signOut()
            }
        }
    }

    /// Esce e toglie dal telefono carte e progressi (restano nel cloud).
    /// `signed_out` + reset di analytics li fa RootGate al cambio di stato.
    private func signOut() {
        isSigningOut = true
        let auth = auth
        let sync = sync
        Task {
            defer { isSigningOut = false }
            do {
                try await auth.signOut()
                sync?.signedOutExplicitly()
            } catch {
                Logger(subsystem: "com.carspot.andrea.app", category: "profile")
                    .error("Uscita non riuscita: \(error.localizedDescription, privacy: .public)")
                showSignOutError = true
            }
        }
    }

    private func sightingRow(_ card: StoredCard) -> some View {
        HStack(spacing: CSSpace.md) {
            Image(systemName: "car.side.fill")
                .font(CSFont.title(18))
                .foregroundStyle(card.rarity.linearGradient)
                .frame(width: CSSpace.lg)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CSSpace.xxs / 2) {
                Text("\(card.make) \(card.model)")
                    .font(CSFont.body(14))
                    .foregroundStyle(CSColor.ink)
                    .lineLimit(1)
                Text(sightingCaption(card))
                    .font(CSFont.caption(12))
                    .foregroundStyle(CSColor.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Zona · data relativa"; la zona si nasconde se vuota.
    private func sightingCaption(_ card: StoredCard) -> String {
        let when = card.capturedAt.formatted(.relative(presentation: .named))
        return card.spottedArea.isEmpty ? when : "\(card.spottedArea) · \(when)"
    }
}

#Preview {
    ZStack { AsphaltBackground(); ProfileView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
