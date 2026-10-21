import SwiftUI
import SwiftData
import os

private let rootLog = Logger(subsystem: "com.carspot.andrea.app", category: "root")

/// Decide cosa mostrare all'avvio: (attesa sessione) → onboarding → login → setup profilo → app.
/// Il login vive in `AppServices.auth` (Clerk o locale); `hasOnboarded` è in `@AppStorage`.
/// Argomenti di debug per gli screenshot: `-skipAuth YES` salta tutto e va all'app
/// (come ospite, con le carte demo); `-showLogin YES` salta l'onboarding e mostra il login; `-resetAuth YES`
/// riparte dall'onboarding; `-sentryTest YES` (solo DEBUG, serve il consenso) invia un
/// errore di prova al report errori.
struct RootGate: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncService.self) private var sync: SyncService?
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var identifiedUserId: String?
    @State private var debugFlagsApplied = false
    /// Nome da spotter e primo setup (`onboarded_at`) dell'utente Clerk.
    @State private var account = ProfileAccount()

    private var auth: any AuthService { AppServices.auth }

    private enum Phase { case loading, onboarding, login, profileSetup, app }

    private var phase: Phase {
        if !auth.isReady { return .loading }
        if !hasOnboarded { return .onboarding }
        switch auth.state {
        case .signedOut:
            return .login
        case .guest:
            return .app
        case .signedIn(let id):
            // Senza Supabase (auth locale) il setup non esiste: mai bloccare.
            guard SupabaseBackend.shared != nil else { return .app }
            // Profilo ancora in caricamento: stesso sfondo neutro dell'attesa sessione.
            guard account.userId == id, let needsSetup = account.needsSetup else { return .loading }
            return needsSetup ? .profileSetup : .app
        }
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
            case .profileSetup:
                ProfileSetupFlow(account: account)
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlow { hasOnboarded = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: phase)
        // Nome da spotter e iniziale dell'avatar per header, Oggi e Profilo.
        .environment(account)
        .task(id: auth.isReady) {
            guard auth.isReady else { return }
            await applyDebugFlags()
            handle(auth.state, from: nil)
            #if DEBUG
            // Dopo `handle`: l'evento di prova porta già l'id utente.
            sendSentryTestIfRequested()
            #endif
        }
        .onChange(of: auth.state) { old, new in
            handle(new, from: old)
        }
        .onChange(of: scenePhase) { _, phase in
            // Ritorno in primo piano: reinvio code + pull (con throttle).
            if phase == .active { Task { await sync?.syncNow() } }
        }
    }

    /// Analytics e profilo cloud reagiscono ai cambi di stato in un punto solo.
    private func handle(_ new: AuthState, from old: AuthState?) {
        switch new {
        case .signedIn(let id):
            guard identifiedUserId != id else { return }
            identifiedUserId = id
            AppServices.analytics.identify(userId: id)
            // Al report errori solo l'id Clerk: mai email, telefono o nome.
            AppServices.errors.setUser(id: id)
            if let backend = SupabaseBackend.shared {
                // Se l'utente ha già finito il setup (cache locale) l'app si apre subito.
                account.prepare(userId: id)
                // Il profilo deve esistere prima della prima carta (FK): poi si legge
                // lo stato del setup e parte il sync.
                Task {
                    do {
                        try await backend.ensureProfile(userId: id)
                    } catch {
                        AppServices.errors.record(error, area: .profile, step: "ensure_profile")
                    }
                    await account.load(userId: id)
                    await sync?.signedIn(userId: id)
                }
            }
        case .signedOut:
            identifiedUserId = nil
            AppServices.errors.setUser(id: nil)
            if let old, old != .signedOut {
                AppServices.analytics.track(.signedOut)
                AppServices.analytics.reset()
            }
        case .guest:
            identifiedUserId = nil
            AppServices.errors.setUser(id: nil)
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
            if auth.state == .signedOut {
                auth.continueAsGuest()
                // Le carte demo esistono solo in questo percorso di debug.
                CardSeeder.seedIfNeeded(context)
            }
        }
        if d.bool(forKey: "showLogin") {
            hasOnboarded = true
            try? await auth.signOut()
        }
    }
}

#if DEBUG
extension RootGate {
    /// `-sentryTest YES`: un errore di prova al report errori (una volta per avvio).
    fileprivate func sendSentryTestIfRequested() {
        guard UserDefaults.standard.bool(forKey: "sentryTest") else { return }
        guard AnalyticsConsentStore.load() == .granted else {
            rootLog.notice("sentryTest: consenso statistiche non dato, Sentry è spento")
            return
        }
        AppServices.errors.breadcrumb("Prova report errori da launch argument", area: .debug)
        AppServices.errors.record(DebugTestError.sentryTest, area: .debug, step: "sentry_test")
        rootLog.notice("sentryTest: errore di prova inviato")
    }
}

/// Errore finto per `-sentryTest`: tipo e codice fissi, così l'issue si raggruppa.
private enum DebugTestError: Error { case sentryTest }
#endif

#Preview {
    RootGate()
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
