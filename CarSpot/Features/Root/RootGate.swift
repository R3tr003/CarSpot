import SwiftUI

/// Decide cosa mostrare all'avvio: (attesa sessione) → onboarding → login → app.
/// Il login vive in `AppServices.auth` (Clerk o locale); `hasOnboarded` è in `@AppStorage`.
/// Argomenti di debug per gli screenshot: `-skipAuth YES` salta tutto e va all'app
/// (come ospite); `-showLogin YES` salta l'onboarding e mostra il login; `-resetAuth YES`
/// riparte dall'onboarding.
struct RootGate: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var identifiedUserId: String?
    @State private var debugFlagsApplied = false

    private var auth: any AuthService { AppServices.auth }

    private enum Phase { case loading, onboarding, login, app }

    private var phase: Phase {
        if !auth.isReady { return .loading }
        if !hasOnboarded { return .onboarding }
        return auth.state == .signedOut ? .login : .app
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                // Sessione salvata ancora in caricamento: sfondo neutro, niente flash di login.
                CSColor.base.ignoresSafeArea()
            case .app:
                RootShellView()
                    .transition(.opacity)
            case .login:
                LoginView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .onboarding:
                OnboardingFlow { hasOnboarded = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: phase)
        .task(id: auth.isReady) {
            guard auth.isReady else { return }
            await applyDebugFlags()
            handle(auth.state, from: nil)
        }
        .onChange(of: auth.state) { old, new in
            handle(new, from: old)
        }
    }

    /// Analytics e profilo cloud reagiscono ai cambi di stato in un punto solo.
    private func handle(_ new: AuthState, from old: AuthState?) {
        switch new {
        case .signedIn(let id):
            guard identifiedUserId != id else { return }
            identifiedUserId = id
            AppServices.analytics.identify(userId: id)
            if let backend = SupabaseBackend.shared {
                Task { try? await backend.ensureProfile(userId: id) }
            }
        case .signedOut:
            identifiedUserId = nil
            if let old, old != .signedOut {
                AppServices.analytics.track(.signedOut)
                AppServices.analytics.reset()
            }
        case .guest:
            identifiedUserId = nil
        }
    }

    private func applyDebugFlags() async {
        guard !debugFlagsApplied else { return }
        debugFlagsApplied = true
        let d = UserDefaults.standard
        if d.bool(forKey: "resetAuth") {
            hasOnboarded = false
            try? await auth.signOut()
        }
        if d.bool(forKey: "skipAuth") {
            hasOnboarded = true
            if auth.state == .signedOut { auth.continueAsGuest() }
        }
        if d.bool(forKey: "showLogin") {
            hasOnboarded = true
            try? await auth.signOut()
        }
    }
}

#Preview {
    RootGate()
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
