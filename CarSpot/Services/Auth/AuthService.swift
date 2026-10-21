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

/// Canale del codice monouso (accesso senza password).
enum CodeChannel: Sendable {
    case email, phone

    /// Valore per `AnalyticsEvent.signedIn(method:)`.
    var analyticsMethod: String {
        switch self {
        case .email: "email"
        case .phone: "phone"
        }
    }
}

/// Errori tipizzati dell'accesso con codice, con messaggio pronto per l'utente.
enum AuthCodeError: LocalizedError, Sendable, Equatable {
    case wrongCode
    case expired
    case invalidIdentifier
    case tooManyAttempts
    /// Il provider non invia SMS verso quel paese (es. Clerk in sviluppo).
    case unsupportedCountry
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .wrongCode:         "Codice non corretto"
        case .expired:           "Codice scaduto, richiedine uno nuovo"
        case .invalidIdentifier: "Email o numero non valido"
        case .tooManyAttempts:   "Troppi tentativi, riprova tra poco"
        case .unsupportedCountry: "Per ora non possiamo mandare SMS a questo numero. Usa l'email o Google."
        case .generic(let msg):  msg
        }
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
    /// Avvia accesso o registrazione e invia il codice. Ritorna quando il codice è partito.
    /// Un solo flusso per utenti nuovi ed esistenti.
    func startCodeSignIn(_ channel: CodeChannel, identifier: String) async throws
    /// Verifica il codice ricevuto; al successo la sessione è attiva (state → .signedIn).
    func verifyCode(_ code: String) async throws
    /// Reinvia il codice per il tentativo in corso.
    func resendCode() async throws
    /// Solo debug `-skipAuth`: stato ospite in memoria, mai persistito.
    func continueAsGuest()
    func signOut() async throws

    /// JWT di sessione per Supabase. Dura ~1 minuto: chiederlo a ogni richiesta, mai
    /// salvarlo. `nil` se ospite o non loggato.
    func sessionToken() async throws -> String?
}
