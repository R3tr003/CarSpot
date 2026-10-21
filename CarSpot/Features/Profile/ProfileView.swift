import SwiftUI
import SwiftData
import os

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync: SyncService?
    @Query private var profiles: [PlayerProfile]
    @Query private var cards: [StoredCard]

    @State private var consent = AppServices.analytics.consent
    @State private var isSigningOut = false
    /// Elementi non ancora nel cloud trovati al logout (> 0 = chiede conferma).
    @State private var unsyncedCount = 0
    @State private var showUnsyncedAlert = false
    private let auth = AppServices.auth

    private var profile: PlayerProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: CSSpace.lg) {
                header
                profileHeader
                statsRow
                myCarCard
                sightingsCard
                privacyCard
                if auth.state != .signedOut { signOutButton }
            }
            .padding(CSSpace.lg)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .alert("Dati non sincronizzati", isPresented: $showUnsyncedAlert) {
            Button("Esci comunque", role: .destructive) { signOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Hai \(unsyncedCount) elementi non ancora salvati nel cloud. Se esci ora li perdi.")
        }
    }

    private var statsRow: some View {
        HStack(spacing: CSSpace.md) {
            statTile("\(cards.count)", "Carte", CSColor.accent)
            statTile("\(profile?.xp ?? 0)", "PE", CSColor.accentWarm)
            statTile("\(profile?.currency ?? 0)", "Valuta", Rarity.epica.primary)
        }
    }

    private func statTile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(CSFont.numeric(24)).foregroundStyle(CSColor.ink)
            Text(label).eyebrow(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CSSpace.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
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
            Text("Cacciatore Livello \(LevelSystem.level(forXP: profile?.xp ?? 0))").eyebrow(CSColor.accent)
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
            guard !isSigningOut else { return }
            isSigningOut = true
            let sync = sync
            Task {
                // Prima si prova a inviare ciò che è in attesa; se resta qualcosa si chiede conferma.
                let left = await sync?.flushPending() ?? 0
                if left > 0 {
                    unsyncedCount = left
                    showUnsyncedAlert = true
                    isSigningOut = false
                } else {
                    signOut()
                }
            }
        } label: {
            Label("Esci", systemImage: "rectangle.portrait.and.arrow.right")
                .font(CSFont.body(16))
                .foregroundStyle(CSColor.accentWarm)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isSigningOut)
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
    ZStack { AsphaltBackground(); ProfileView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
