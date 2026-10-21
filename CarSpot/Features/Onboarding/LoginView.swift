import SwiftUI

/// Login in stile Flighty: sfondo animato a puntini, titolo e i due pulsanti
/// "Accedi con Apple" / "Accedi con Google" più email e telefono (codice monouso, sheet
/// `CodeSignInView`). L'auth passa da `AppServices.auth`
/// (Clerk, o login simulato senza chiavi); `RootGate` reagisce al cambio di stato,
/// quindi qui non serve nessuna callback.
struct LoginView: View {
    @State private var working = false
    @State private var errorMessage: String?
    /// Canale del codice monouso: se presente, mostra la sheet email/telefono.
    @State private var codeChannel: CodeChannel?

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

            VStack(spacing: 0) {
                Spacer()

                // Marchio.
                Image(systemName: "car.side.fill")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(Rarity.rara.linearGradient)
                    .shadow(color: Rarity.rara.primary.opacity(0.6), radius: 24, y: 10)

                VStack(spacing: CSSpace.sm) {
                    Text("BENVENUTO").eyebrow(Rarity.rara.primary)
                    Text("Inizia la caccia")
                        .font(CSFont.display(36))
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
                    }

                    // Stesso aspetto del pulsante di sistema (bianco, capsula); Clerk apre
                    // da solo il suo prompt Apple, quindi niente `SignInWithAppleButton`
                    // (farebbe partire un secondo prompt).
                    Button {
                        signIn(method: "apple") { try await AppServices.auth.signInWithApple() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo").font(.system(size: 18, weight: .semibold))
                            Text("Accedi con Apple").font(CSFont.title(17))
                        }
                        .foregroundStyle(CSColor.base)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white, in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button {
                        signIn(method: "google") { try await AppServices.auth.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill").font(.system(size: 18, weight: .bold))
                            Text("Accedi con Google").font(CSFont.title(17))
                        }
                        .foregroundStyle(CSColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)

                    codeButton("Continua con email", icon: "envelope.fill", channel: .email)
                    codeButton("Continua con telefono", icon: "phone.fill", channel: .phone)
                }
                .disabled(working)
                .padding(.horizontal, CSSpace.xl)
                .padding(.bottom, CSSpace.xxl)
            }

            if working {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(CSColor.accent)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $codeChannel) { CodeSignInView(channel: $0) }
    }

    /// Pulsante "Continua con…" per l'accesso con codice (stessa famiglia del tasto Google).
    private func codeButton(_ title: String, icon: String, channel: CodeChannel) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            errorMessage = nil
            codeChannel = channel
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(CSFont.title(17))
            }
            .foregroundStyle(CSColor.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// Esegue il login; l'annullamento dell'utente non lancia (il servizio lo assorbe).
    private func signIn(method: String, _ action: @escaping () async throws -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                errorMessage = "Accesso non riuscito. Riprova tra poco."
            }
        }
    }
}

#Preview {
    LoginView()
}
