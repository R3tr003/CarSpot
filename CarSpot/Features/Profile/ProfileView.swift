import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileAccount.self) private var account: ProfileAccount?
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \StoredCard.capturedAt, order: .reverse) private var cards: [StoredCard]

    @State private var showAvatarPicker = false
    @State private var avatarError: String?

    private let auth = AppServices.auth

    private var profile: PlayerProfile? { profiles.first }

    /// Nome mostrato: handle dello spotter, o un fallback se non ancora scelto.
    private var displayName: String {
        guard let name = account?.username, !name.isEmpty else { return String(localized: "Spotter") }
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
            }
            .padding(CSSpace.lg)
            .padding(.bottom, CSSpace.xl)
        }
        .scrollIndicators(.hidden)
        .avatarPicker(
            isPresented: $showAvatarPicker,
            hasPhoto: account?.avatar != nil,
            onPicked: { jpeg in changeAvatar { try await $0.setAvatar(jpeg: jpeg) } },
            onRemove: { changeAvatar { try await $0.removeAvatar() } }
        )
        .alert("Foto profilo", isPresented: Binding(
            get: { avatarError != nil },
            set: { if !$0 { avatarError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(avatarError ?? "")
        }
    }

    /// Foto modificabile solo con un profilo cloud (account + backend).
    private var canEditAvatar: Bool { account != nil && SupabaseBackend.shared != nil }

    private func changeAvatar(_ action: @escaping (ProfileAccount) async throws -> Void) {
        guard let account else { return }
        Task {
            do {
                try await action(account)
            } catch {
                avatarError = AppError.shown(for: error, fallback: .saveAvatarFailed)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: CSSpace.md) {
            statTile(cards.count, "Carte", CSColor.accent)
            statTile(profile?.xp ?? 0, "PE", CSColor.accentWarm, spoken: "Punti esperienza")
            statTile(profile?.currency ?? 0, "Valuta", Rarity.epica.primary)
        }
    }

    private func statTile(_ value: Int, _ label: LocalizedStringKey, _ tint: Color, spoken: LocalizedStringKey? = nil) -> some View {
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
            avatarView
            Text(displayName)
                .font(CSFont.display(26))
                .foregroundStyle(CSColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // Nome e cognome (privati, da Clerk): solo se presenti.
            if let fullName = auth.personName?.fullName, !fullName.isEmpty {
                Text(fullName)
                    .font(CSFont.body(15))
                    .foregroundStyle(CSColor.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("Cacciatore Livello \(progress.level)").eyebrow(CSColor.accent)
            levelProgress(progress)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CSSpace.xs)
    }

    /// Avatar grande: con profilo cloud è un bottone che apre il menu foto.
    @ViewBuilder
    private var avatarView: some View {
        let avatar = UserAvatar(size: 88, name: account?.username ?? "", avatar: account?.avatar)
        if canEditAvatar {
            Button { showAvatarPicker = true } label: {
                avatar
                    .overlay { if account?.isAvatarBusy == true { avatarSpinner } }
                    .overlay(alignment: .bottomTrailing) { cameraBadge }
                    .accessibilityElement(children: .ignore)
            }
            .buttonStyle(CSPressStyle())
            .disabled(account?.isAvatarBusy == true)
            .accessibilityLabel("Cambia foto profilo")
        } else {
            avatar.accessibilityHidden(true)
        }
    }

    private var avatarSpinner: some View {
        ZStack {
            Circle().fill(CSColor.base.opacity(0.55))
            ProgressView().tint(CSColor.ink)
        }
    }

    private var cameraBadge: some View {
        Image(systemName: "camera.fill")
            .font(CSFont.caption(12))
            .foregroundStyle(CSColor.ink)
            .frame(width: CSSpace.lg + CSSpace.xxs, height: CSSpace.lg + CSSpace.xxs)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }

    private func levelProgress(_ progress: (level: Int, into: Int, needed: Int, fraction: Double)) -> some View {
        let hasXP = (profile?.xp ?? 0) > 0
        return VStack(spacing: CSSpace.xs) {
            StatBar(
                label: "Livello \(progress.level)",
                value: Int((progress.fraction * 100).rounded(.down)),
                tint: CSColor.accent,
                animate: false,
                valueText: String(localized: "\(progress.into) / \(progress.needed) PE")
            )
            Text(levelHint(hasXP: hasXP, progress: progress))
                .font(CSFont.caption(12))
                .foregroundStyle(CSColor.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, CSSpace.xs)
    }

    /// Stringa già localizzata: il testo dipende dai punti esperienza.
    private func levelHint(hasXP: Bool, progress: (level: Int, into: Int, needed: Int, fraction: Double)) -> String {
        hasXP
            ? String(localized: "\(progress.needed - progress.into) PE al livello \(progress.level + 1)")
            : String(localized: "Fotografa la prima auto per salire di livello")
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
        let when = card.capturedAt.formatted(.relative(presentation: .named).locale(.app))
        return card.spottedArea.isEmpty ? when : "\(card.spottedArea) · \(when)"
    }
}

#Preview {
    ZStack { AsphaltBackground(); ProfileView() }
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
