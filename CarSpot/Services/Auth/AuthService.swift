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
        case .wrongCode:         String(localized: "Codice non corretto")
        case .expired:           String(localized: "Codice scaduto, richiedine uno nuovo")
        case .invalidIdentifier: String(localized: "Email o numero non valido")
        case .tooManyAttempts:   String(localized: "Troppi tentativi, riprova tra poco")
        case .unsupportedCountry: String(localized: "Per ora non possiamo mandare SMS a questo numero. Usa l'email o Google.")
        case .generic(let msg):  msg
        }
    }
}

/// Nome e cognome reali dell'utente. Vivono SOLO in Clerk (mai in Supabase) e sono
/// privati: non li vedono gli altri spotter.
struct PersonName: Equatable, Sendable {
    var first: String
    var last: String

    /// Nome e cognome separati da uno spazio, senza parti vuote.
    var fullName: String {
        [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isEmpty: Bool { first.isEmpty && last.isEmpty }

    /// Ritaglia gli spazi; `nil` se resta tutto vuoto.
    init?(first: String?, last: String?) {
        let f = (first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let l = (last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty || !l.isEmpty else { return nil }
        self.first = f
        self.last = l
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
    /// Elimina definitivamente l'account (Guideline 5.1.1(v)). Con Clerk cancella l'utente;
    /// la pulizia su Supabase (profilo, carte, foto) la fa il webhook `user.deleted`.
    /// Al successo `state` torna `.signedOut`.
    func deleteAccount() async throws

    /// Nome e cognome dell'utente, se presenti (con Google arrivano già da Clerk).
    var personName: PersonName? { get }
    /// Salva nome e cognome (solo in Clerk). Lancia se offline o se Clerk rifiuta.
    func updatePersonName(first: String, last: String) async throws
    /// Foto dell'account del provider (Google; Apple quando tornerà), se l'utente ne ha una.
    var accountImageURL: URL? { get }

    /// JWT di sessione per Supabase. Dura ~1 minuto: chiederlo a ogni richiesta, mai
    /// salvarlo. `nil` se ospite o non loggato.
    func sessionToken() async throws -> String?
}
