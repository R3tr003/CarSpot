import SwiftUI
import AuthenticationServices

/// Login in stile Flighty: sfondo animato a puntini, titolo e i due pulsanti
/// "Accedi con Apple" / "Accedi con Google". Per ora l'autenticazione è un
/// placeholder locale (segna l'utente come loggato); il token reale Supabase
/// verrà collegato in una fase successiva.
struct LoginView: View {
    var onSignedIn: () -> Void

    @State private var working = false

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
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        // A prescindere dall'esito (entitlement non attivo sul
                        // simulatore) entriamo nell'app: l'auth reale arriva dopo.
                        finishSignIn()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(Capsule())

                    Button {
                        finishSignIn()
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

                    Button("Continua senza account") { finishSignIn() }
                        .font(CSFont.caption(14))
                        .foregroundStyle(CSColor.inkSecondary)
                        .padding(.top, CSSpace.xs)
                }
                .padding(.horizontal, CSSpace.xl)
                .padding(.bottom, CSSpace.xxl)
            }

            if working {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(CSColor.accent)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func finishSignIn() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSignedIn()
    }
}

#Preview {
    LoginView(onSignedIn: {})
}
