import Foundation

/// Stato di autenticazione visto dall'app.
enum AuthState: Equatable, Sendable {
    /// Nessuna sessione: mostrare il login.
    case signedOut
    /// Solo debug (`-skipAuth YES`, screenshot su simulatore): app utilizzabile senza account,
    /// dati solo in locale, niente sync. Non c'è nessuna UI per entrarci né viene persistito.
    case guest
    /// Sessione Clerk attiva. `userId` = Clerk user id ("user_…") = `auth.jwt()->>'sub'`
    /// lato Supabase.
    case signedIn(userId: String)

    var userId: String? {
        if case .signedIn(let id) = self { id } else { nil }
    }
}

/// Autenticazione dietro protocollo (convenzione del progetto): implementazione Clerk
/// quando `AppConfig.isClerkConfigured`, altrimenti locale (login simulato, offline).
/// Le implementazioni sono `@Observable`: le view che leggono `state` si aggiornano da sole.
@MainActor
protocol AuthService: AnyObject {
    var state: AuthState { get }
    /// `false` finché la sessione salvata non è stata caricata (evita di mostrare il
    /// login per un attimo a chi è già loggato).
    var isReady: Bool { get }

    func signInWithApple() async throws
    func signInWithGoogle() async throws
    /// Solo debug `-skipAuth`: stato ospite in memoria, mai persistito.
    func continueAsGuest()
    func signOut() async throws

    /// JWT di sessione per Supabase. Dura ~1 minuto: chiederlo a ogni richiesta, mai
    /// salvarlo. `nil` se ospite o non loggato.
    func sessionToken() async throws -> String?
}
