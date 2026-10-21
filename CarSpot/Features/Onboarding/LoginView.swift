import SwiftUI

/// Login in stile Flighty: sfondo animato a puntini, titolo e i due pulsanti
/// "Continua con Apple" / "Continua con Google" più email e telefono (codice monouso, sheet
/// `CodeSignInView`). L'auth passa da `AppServices.auth`
/// (Clerk, o login simulato senza chiavi); `RootGate` reagisce al cambio di stato,
/// quindi qui non serve nessuna callback.
struct LoginView: View {
    @State private var working = false
    @State private var errorMessage: String?
    /// Canale del codice monouso: se presente, mostra la sheet email/telefono.
    @State private var codeChannel: CodeChannel?
    /// Cambia a ogni tocco su un metodo di accesso: fa partire l'haptic.
    @State private var taps = 0

    var body: some View {
        ZStack {
            CSColor.base.ignoresSafeArea()
            DottedBackdrop(tint: Rarity.rara.primary).ignoresSafeArea()

            // Aurora morbida in alto per profondità.
            RadialGradient(
                colors: [Rarity.rara.primary.opacity(0.25), .clear],
                center: .top, startRadius: 4, endRadius: 420
            )
            .ignoresSafeArea()

            // Scrollabile per i Dynamic Type molto grandi; quando il contenuto ci sta
            // il layout resta quello a tutta altezza (nessun rimbalzo).
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            if working {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(CSColor.accent)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $codeChannel) { CodeSignInView(channel: $0) }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            // Marchio.
            Image(systemName: "car.side.fill")
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(Rarity.rara.linearGradient)
                .shadow(color: Rarity.rara.primary.opacity(0.6), radius: 24, y: 10)
                .accessibilityHidden(true)

            VStack(spacing: CSSpace.sm) {
                Text("Benvenuto").eyebrow(Rarity.rara.primary)
                Text("Inizia la caccia")
                    .font(CSFont.display(36))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.ink)
                Text("Accedi per salvare la tua collezione e ritrovarla su ogni dispositivo.")
                    .font(CSFont.body(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.inkSecondary)
                    .padding(.horizontal, CSSpace.xl)
            }
            .padding(.top, CSSpace.lg)

            Spacer()

            VStack(spacing: CSSpace.sm) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                // Solo con la capability attiva (vedi `AppConfig.isAppleSignInEnabled`).
                // Stesso aspetto del pulsante di sistema (bianco, capsula); Clerk apre
                // da solo il suo prompt Apple, quindi niente `SignInWithAppleButton`
                // (farebbe partire un secondo prompt).
                if AppConfig.isAppleSignInEnabled {
                    Button {
                        signIn(method: "apple") { try await AppServices.auth.signInWithApple() }
                    } label: {
                        HStack(spacing: CSSpace.xs) {
                            Image(systemName: "apple.logo").font(CSFont.title(17))
                            Text("Continua con Apple").font(CSFont.title(17))
                        }
                        .foregroundStyle(CSColor.inkInverse)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(CSColor.appleButton, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(CSPressStyle())
                }

                GlassEffectContainer(spacing: CSSpace.sm) {
                    VStack(spacing: CSSpace.sm) {
                        glassButton("Continua con Google", icon: "g.circle.fill") {
                            signIn(method: "google") { try await AppServices.auth.signInWithGoogle() }
                        }
                        glassButton("Continua con email", icon: "envelope.fill") { openCode(.email) }
                        glassButton("Continua con telefono", icon: "phone.fill") { openCode(.phone) }
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: errorMessage)
            .disabled(working)
            .padding(.horizontal, CSSpace.xl)
            .padding(.bottom, CSSpace.xxl)
        }
    }

    /// Pulsante in vetro nativo, stessa famiglia per Google, email e telefono.
    private func glassButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CSSpace.xs) {
                Image(systemName: icon).font(CSFont.title(17))
                Text(title).font(CSFont.title(17))
            }
            .foregroundStyle(CSColor.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(CSPressStyle())
    }

    private func openCode(_ channel: CodeChannel) {
        taps += 1
        errorMessage = nil
        codeChannel = channel
    }

    /// Esegue il login; l'annullamento dell'utente non lancia (il servizio lo assorbe).
    private func signIn(method: String, _ action: @escaping () async throws -> Void) {
        taps += 1
        errorMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await action()
                if AppServices.auth.state != .signedOut {
                    AppServices.analytics.track(.signedIn(method: method))
                }
            } catch {
                // Il servizio ha già registrato l'errore inatteso (`ErrorReporting`).
                let message = AppError.message(for: error, fallback: .signInFailed)
                errorMessage = message
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}

#Preview {
    LoginView()
}
