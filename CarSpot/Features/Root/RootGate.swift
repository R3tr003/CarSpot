import SwiftUI

/// Decide cosa mostrare all'avvio: onboarding → login → app.
/// Lo stato è persistito con `@AppStorage`. Argomenti di debug per gli screenshot:
/// `-skipAuth YES` salta tutto e va all'app; `-showLogin YES` salta l'onboarding
/// e mostra il login; `-resetAuth YES` riazzera i flag.
struct RootGate: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("isSignedIn") private var isSignedIn = false

    var body: some View {
        Group {
            if isSignedIn {
                RootShellView()
                    .transition(.opacity)
            } else if hasOnboarded {
                LoginView { signIn() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                OnboardingFlow { withAnimation(.easeInOut) { hasOnboarded = true } }
                    .transition(.opacity)
            }
        }
        .onAppear(perform: applyDebugFlags)
    }

    private func signIn() {
        withAnimation(.easeInOut) { isSignedIn = true }
    }

    private func applyDebugFlags() {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetAuth") { hasOnboarded = false; isSignedIn = false }
        if d.bool(forKey: "skipAuth") { hasOnboarded = true; isSignedIn = true }
        if d.bool(forKey: "showLogin") { hasOnboarded = true; isSignedIn = false }
    }
}

#Preview {
    RootGate()
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
