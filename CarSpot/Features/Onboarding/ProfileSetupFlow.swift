import SwiftUI

/// Primo setup del profilo, mostrato una sola volta dopo il primo accesso:
/// benvenuto → nome e cognome → nome da spotter → permessi → foto → pronto. Non si salta; solo il passo permessi è
/// facoltativo al suo interno. `RootGate` lo mostra finché `account.needsSetup == true`.
struct ProfileSetupFlow: View {
    let account: ProfileAccount

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var checker: UsernameChecker
    @State private var location = LocationManager()
    @State private var working = false
    @State private var errorMessage: String?
    @State private var firstName: String
    @State private var lastName: String
    @FocusState private var nameFocused: Bool
    @FocusState private var realNameFocus: RealNameField?

    // 0 benvenuto · 1 nome e cognome · 2 nome da spotter · 3 permessi · 4 foto · 5 pronto
    private let stepCount = 6
    private static let rarities: [Rarity] = [.rara, .rara, .rara, .epica, .epica, .leggendaria]

    init(account: ProfileAccount) {
        self.account = account
        // Con Google nome e cognome arrivano già da Clerk: precompilati.
        let known = AppServices.auth.personName
        _firstName = State(initialValue: known?.first ?? "")
        _lastName = State(initialValue: known?.last ?? "")
        _checker = State(initialValue: UsernameChecker(current: account.username))
    }

    /// Nomi stabili dei passi per le statistiche, nello stesso ordine di `step`.
    private static let stepNames = ["welcome", "real_name", "username", "permissions", "photo", "done"]

    private var rarity: Rarity { Self.rarities[step] }

    var body: some View {
        ZStack {
            CSColor.base.ignoresSafeArea()
            // Solo il colore cambia con il passo: dissolvenza morbida (niente con Reduce Motion).
            Group {
                DottedBackdrop(tint: rarity.primary).ignoresSafeArea()
                RadialGradient(
                    colors: [rarity.primary.opacity(0.25), .clear],
                    center: .top, startRadius: 4, endRadius: 420
                )
                .ignoresSafeArea()
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: step)

            VStack(spacing: 0) {
                backBar
                pager
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: step, initial: true) { _, new in
            guard Self.stepNames.indices.contains(new) else { return }
            AppServices.errors.metric(count: "setup.step", attributes: ["step": .string(Self.stepNames[new])])
        }
        // Ai passi con campi la tastiera si apre a transizione finita.
        .task(id: step) {
            guard step == 1 || step == 2 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if step == 2 {
                nameFocused = true
            } else if firstName.isEmpty {
                realNameFocus = .first
            } else if lastName.isEmpty {
                realNameFocus = .last
            }
        }
    }

    // MARK: - Struttura

    /// Freccia indietro (dal nome in poi) e avanzamento a 5 segmenti; sul benvenuto
    /// restano come spazio vuoto.
    private var backBar: some View {
        HStack {
            Button {
                go(to: step - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(CSFont.title(17))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: CSSize.minTap, height: CSSize.minTap)
                    .glassEffect(.regular, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Indietro")
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0 || working)
            .accessibilityHidden(step == 0)
            Spacer()
            progressIndicator
            Spacer()
            // Stessa larghezza della freccia: l'indicatore resta centrato.
            Color.clear.frame(width: CSSize.minTap, height: CSSize.minTap)
        }
        .padding(.horizontal, CSSpace.lg)
        .padding(.top, CSSpace.sm)
    }

    /// Cinque segmenti: accent per i passi fatti e quello attuale (passi 1-5; il benvenuto è a zero).
    private var progressIndicator: some View {
        HStack(spacing: CSSpace.xs) {
            ForEach(1...5, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? CSColor.accent : CSColor.hairline)
                    .frame(width: CSSpace.lg, height: CSSpace.xxs)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: step)
        .opacity(step == 0 ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passo \(max(step, 1)) di 5")
        .accessibilityHidden(step == 0)
    }

    /// Le sei pagine affiancate: scorrono in orizzontale con una molla senza rimbalzo
    /// (o dissolvenza incrociata con "Riduci movimento").
    private var pager: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<stepCount, id: \.self) { index in
                    page(index)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: reduceMotion ? 0 : CGFloat(index - step) * geo.size.width)
                        .opacity(reduceMotion && index != step ? 0 : 1)
                        .allowsHitTesting(index == step)
                        .accessibilityHidden(index != step)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        switch index {
        case 0:
            ProfileSetupWelcomeStep()
        case 1:
            ProfileSetupRealNameStep(
                first: $firstName,
                last: $lastName,
                focused: $realNameFocus,
                errorMessage: step == 1 ? errorMessage : nil,
                onSubmit: { if canAdvance && !working { advance() } }
            )
        case 2:
            ProfileSetupNameStep(
                account: account,
                checker: checker,
                focused: $nameFocused,
                errorMessage: step == 2 ? errorMessage : nil,
                onSubmit: { if canAdvance && !working { advance() } }
            )
        case 3:
            ProfileSetupPermissionsStep(location: location)
        case 4:
            ProfileSetupPhotoStep(account: account, errorMessage: step == 4 ? errorMessage : nil)
        default:
            ProfileSetupReadyStep(username: checker.text, avatar: account.avatar,
                                  errorMessage: step == 5 ? errorMessage : nil)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: CSSpace.xs) {
            // Durante il lavoro lo spinner prende il posto del titolo.
            PrimaryButton(
                title: working ? "" : ctaTitle,
                icon: working ? nil : ctaIcon,
                gradient: rarity.gradient
            ) {
                advance()
            }
            .disabled(!canAdvance || working)
            .opacity(canAdvance && !working ? 1 : 0.4)
            .overlay { if working { ProgressView().tint(CSColor.inkInverse) } }
            .accessibilityLabel(ctaTitle)
            .accessibilityValue(workingSpoken)

            // Errore di rete: l'utente non resta mai bloccato.
            if errorMessage != nil && !working {
                Button {
                    account.skipSetupForNow()
                } label: {
                    Text("Continua più tardi")
                        .font(CSFont.body(15))
                        .foregroundStyle(CSColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: CSSize.minTap)
                        .contentShape(.rect)
                }
                .buttonStyle(CSPressStyle())
            }
        }
        .padding(.horizontal, CSSpace.xl)
        .padding(.top, CSSpace.md)
        .safeAreaPadding(.bottom, CSSpace.md)
    }

    private var ctaTitle: LocalizedStringKey {
        switch step {
        case 0: "Iniziamo"
        case 4: account.avatar != nil ? "Continua" : "Salta per ora"
        case stepCount - 1: "Entra in CarSpot"
        default: "Continua"
        }
    }
    private var workingSpoken: LocalizedStringKey { working ? "In corso" : "" }
    private var ctaIcon: String { step == stepCount - 1 ? "flag.checkered" : "arrow.right" }
    private var canAdvance: Bool {
        switch step {
        case 1: ProfileSetupRealNameStep.isValid(first: firstName, last: lastName)
        case 2: checker.canContinue
        case 4: !account.isAvatarBusy
        default: true
        }
    }

    // MARK: - Azioni

    private func go(to target: Int) {
        guard (0..<stepCount).contains(target) else { return }
        nameFocused = false
        realNameFocus = nil
        errorMessage = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0)) {
            step = target
        }
    }

    private func advance() {
        errorMessage = nil
        switch step {
        case 0: go(to: 1)
        case 1: saveRealName()
        case 2: saveName()
        case 3: go(to: 4)
        case 4: go(to: 5)
        default: finish()
        }
    }

    /// Nome e cognome vanno solo in Clerk. Se non cambiano rispetto a Clerk non c'è rete;
    /// in caso di errore resta il pulsante "Continua più tardi" (mai bloccati).
    private func saveRealName() {
        guard ProfileSetupRealNameStep.isValid(first: firstName, last: lastName) else { return }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if AppServices.auth.personName == PersonName(first: first, last: last) {
            go(to: 2)
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                try await AppServices.auth.updatePersonName(first: first, last: last)
                AppServices.errors.metric(count: "profile.edit", attributes: ["field": "name", "origin": "setup"])
                go(to: 2)
            } catch {
                errorMessage = AppError.shown(for: error, fallback: .saveRealNameFailed)
            }
        }
    }

    private func saveName() {
        guard checker.canContinue else { return }
        if checker.status == .unchanged {
            go(to: 3)
            return
        }
        let value = checker.text
        working = true
        Task {
            defer { working = false }
            do {
                try await account.saveUsername(value)
                AppServices.errors.metric(count: "profile.edit", attributes: ["field": "username", "origin": "setup"])
                checker.markSaved()
                go(to: 3)
            } catch ProfileAccountError.usernameTaken {
                checker.markTaken()
            } catch {
                errorMessage = AppError.shown(for: error, fallback: .saveNameFailed)
            }
        }
    }

    private func finish() {
        working = true
        Task {
            defer { working = false }
            do {
                try await account.completeOnboarding()
                AppServices.analytics.track(.profileSetupCompleted)
                // RootGate vede `needsSetup == false` e passa all'app.
            } catch {
                errorMessage = AppError.shown(for: error, fallback: .completeSetupFailed)
            }
        }
    }
}

// MARK: - Scaffold condiviso delle pagine

/// Intestazione (eyebrow + titolo + sottotitolo) e contenuto, centrati e scrollabili
/// (tastiera e Dynamic Type grandi non tagliano nulla).
struct ProfileSetupPage<Content: View>: View {
    var eyebrow: LocalizedStringKey
    var title: LocalizedStringKey
    /// Riga opzionale sotto il titolo (es. l'handle "@nome"), su una sola riga.
    var handle: String? = nil
    var subtitle: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: CSSpace.xl) {
                    VStack(spacing: CSSpace.sm) {
                        Text(eyebrow).eyebrow(CSColor.accent)
                        Text(title)
                            .font(CSFont.display(32))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(CSColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        if let handle {
                            Text(handle)
                                .font(CSFont.display(26))
                                .foregroundStyle(CSColor.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        Text(subtitle)
                            .font(CSFont.body(15))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(CSColor.inkSecondary)
                            .padding(.horizontal, CSSpace.md)
                    }
                    content
                }
                .padding(.horizontal, CSSpace.lg)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Passo 5 · Pronto

private struct ProfileSetupReadyStep: View {
    var username: String
    var avatar: AvatarRef?
    var errorMessage: String?

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 5 DI 5",
            title: "Sei pronto",
            handle: "@\(username)",
            subtitle: "Inquadra la prima auto che ti colpisce: diventerà la tua prima carta."
        ) {
            VStack(spacing: CSSpace.md) {
                if avatar != nil {
                    UserAvatar(size: 96, name: username, avatar: avatar)
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 88, weight: .black))
                        .foregroundStyle(Rarity.leggendaria.linearGradient)
                        .shadow(color: Rarity.leggendaria.primary.opacity(0.5), radius: 24, y: 10)
                        .accessibilityHidden(true)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

#Preview {
    ProfileSetupFlow(account: ProfileAccount())
}
