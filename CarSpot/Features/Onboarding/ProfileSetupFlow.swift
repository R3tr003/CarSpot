import SwiftUI

/// Primo setup del profilo, mostrato una sola volta dopo il primo accesso:
/// nome da spotter → permessi → pronto. Non si salta; solo il passo permessi è
/// facoltativo al suo interno. `RootGate` lo mostra finché `account.needsSetup == true`.
struct ProfileSetupFlow: View {
    let account: ProfileAccount

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var checker: UsernameChecker
    @State private var location = LocationManager()
    @State private var working = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private let stepCount = 3
    private static let rarities: [Rarity] = [.rara, .epica, .leggendaria]

    init(account: ProfileAccount) {
        self.account = account
        _checker = State(initialValue: UsernameChecker(current: account.username))
    }

    private var rarity: Rarity { Self.rarities[step] }

    var body: some View {
        ZStack {
            CSColor.base.ignoresSafeArea()
            DottedBackdrop(tint: rarity.primary).ignoresSafeArea()
            RadialGradient(
                colors: [rarity.primary.opacity(0.25), .clear],
                center: .top, startRadius: 4, endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                backBar
                pager
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.4), value: step)
    }

    // MARK: - Struttura

    /// Freccia indietro (passi 2-3); sul primo passo resta come spazio vuoto.
    private var backBar: some View {
        HStack {
            Button {
                go(to: step - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CSColor.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Indietro")
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0 || working)
            .accessibilityHidden(step == 0)
            Spacer()
        }
        .padding(.horizontal, CSSpace.lg)
        .padding(.top, CSSpace.sm)
    }

    /// Le tre pagine affiancate: scorrono in orizzontale con una molla senza rimbalzo
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
            ProfileSetupNameStep(account: account, checker: checker, focused: $nameFocused, errorMessage: step == 0 ? errorMessage : nil)
        case 1:
            ProfileSetupPermissionsStep(location: location)
        default:
            ProfileSetupReadyStep(username: checker.text, errorMessage: step == 2 ? errorMessage : nil)
        }
    }

    private var bottomBar: some View {
        PrimaryButton(title: ctaTitle, icon: ctaIcon, gradient: rarity.gradient) {
            advance()
        }
        .disabled(!canAdvance || working)
        .opacity(canAdvance && !working ? 1 : 0.4)
        .overlay { if working { ProgressView().tint(.black) } }
        .padding(.horizontal, CSSpace.xl)
        .padding(.top, CSSpace.md)
        .padding(.bottom, CSSpace.xxl)
    }

    private var ctaTitle: String { step == stepCount - 1 ? "Inizia" : "Continua" }
    private var ctaIcon: String { step == stepCount - 1 ? "flag.checkered" : "arrow.right" }
    private var canAdvance: Bool { step == 0 ? checker.canContinue : true }

    // MARK: - Azioni

    private func go(to target: Int) {
        guard (0..<stepCount).contains(target) else { return }
        nameFocused = false
        errorMessage = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0)) {
            step = target
        }
    }

    private func advance() {
        errorMessage = nil
        switch step {
        case 0: saveName()
        case 1: go(to: 2)
        default: finish()
        }
    }

    private func saveName() {
        guard checker.canContinue else { return }
        if checker.status == .unchanged {
            go(to: 1)
            return
        }
        let value = checker.text
        working = true
        Task {
            defer { working = false }
            do {
                try await account.saveUsername(value)
                checker.markSaved()
                go(to: 1)
            } catch ProfileAccountError.usernameTaken {
                checker.markTaken()
            } catch let error as ProfileAccountError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Non riesco a salvare il nome. Controlla la connessione e riprova."
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
                errorMessage = "Non riesco a completare ora. Controlla la connessione e riprova."
            }
        }
    }
}

// MARK: - Scaffold condiviso delle pagine

/// Intestazione (eyebrow + titolo + sottotitolo) e contenuto, centrati e scrollabili
/// (tastiera e Dynamic Type grandi non tagliano nulla).
struct ProfileSetupPage<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
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

// MARK: - Passo 3 · Pronto

private struct ProfileSetupReadyStep: View {
    var username: String
    var errorMessage: String?

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 3 DI 3",
            title: "Sei pronto, @\(username)",
            subtitle: "Inquadra la prima auto che ti colpisce: diventerà la tua prima carta."
        ) {
            VStack(spacing: CSSpace.md) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 88, weight: .black))
                    .foregroundStyle(Rarity.leggendaria.linearGradient)
                    .shadow(color: Rarity.leggendaria.primary.opacity(0.5), radius: 24, y: 10)
                    .accessibilityHidden(true)
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
