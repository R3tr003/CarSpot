import Foundation
import AuthenticationServices
import ClerkKit
import os

/// Auth reale via Clerk. Solo con `AppConfig.isClerkConfigured` (Clerk va configurato in
/// `CarSpotApp.init`: toccare `Clerk.shared` prima assert in debug).
/// `state` legge `Clerk.shared.user` (osservabile): le view si aggiornano da sole.
@MainActor
@Observable
final class ClerkAuthService: AuthService {
    /// Chiave dell'ex modalità ospite persistita: oggi viene solo rimossa all'avvio.
    private static let legacyGuestKey = "clerkGuestMode"
    private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "auth")

    /// Ospite solo in memoria (debug `-skipAuth`). Stored property per essere osservata.
    private var isGuest = false

    /// Tentativo di accesso/registrazione col codice in corso (serve a verify/resend).
    private enum CodeAttempt {
        case signIn(SignIn, CodeChannel)
        case signUp(SignUp, CodeChannel)
    }
    @ObservationIgnored private var codeAttempt: CodeAttempt?

    init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyGuestKey)
    }

    var state: AuthState {
        if let user = Clerk.shared.user { return .signedIn(userId: user.id) }
        return isGuest ? .guest : .signedOut
    }

    var isReady: Bool { Clerk.shared.isLoaded }

    func signInWithApple() async throws {
        try await perform { try await Clerk.shared.auth.signInWithApple() }
    }

    func signInWithGoogle() async throws {
        try await perform { try await Clerk.shared.auth.signInWithOAuth(provider: .google) }
    }

    func startCodeSignIn(_ channel: CodeChannel, identifier: String) async throws {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw AuthCodeError.invalidIdentifier }
        do {
            // Prima accesso (invia già il codice); se l'account non esiste → registrazione.
            let signIn = switch channel {
            case .email: try await Clerk.shared.auth.signInWithEmailCode(emailAddress: id)
            case .phone: try await Clerk.shared.auth.signInWithPhoneCode(phoneNumber: id)
            }
            codeAttempt = .signIn(signIn, channel)
        } catch let e as ClerkAPIError where Self.notFoundCodes.contains(e.code) {
            do {
                var signUp = switch channel {
                case .email: try await Clerk.shared.auth.signUp(emailAddress: id)
                case .phone: try await Clerk.shared.auth.signUp(phoneNumber: id)
                }
                signUp = switch channel {
                case .email: try await signUp.sendEmailCode()
                case .phone: try await signUp.sendPhoneCode()
                }
                codeAttempt = .signUp(signUp, channel)
            } catch {
                throw fail("Registrazione col codice fallita", error)
            }
        } catch {
            throw fail("Invio codice fallito", error)
        }
    }

    func verifyCode(_ code: String) async throws {
        guard let attempt = codeAttempt else { throw AuthCodeError.expired }
        do {
            switch attempt {
            case .signIn(let signIn, _):
                let result = try await signIn.verifyCode(code)
                guard result.status == .complete, let sessionId = result.createdSessionId else {
                    if result.firstFactorVerification?.status == .expired { throw AuthCodeError.expired }
                    Self.log.error("Accesso non completato, stato: \(result.status.rawValue, privacy: .public)")
                    throw AuthCodeError.generic(Self.debugSuffix("Accesso non completato. Riprova.",
                                                                 "stato \(result.status.rawValue)"))
                }
                try await activate(sessionId: sessionId)
            case .signUp(let signUp, let channel):
                let result = switch channel {
                case .email: try await signUp.verifyEmailCode(code)
                case .phone: try await signUp.verifyPhoneCode(code)
                }
                guard result.status == .complete, let sessionId = result.createdSessionId else {
                    let key = channel == .email ? "email_address" : "phone_number"
                    if result.verifications[key]??.status == .expired { throw AuthCodeError.expired }
                    let missing = result.missingFields.map(\.rawValue).joined(separator: ",")
                    Self.log.error("Registrazione incompleta: stato \(String(describing: result.status), privacy: .public), campi mancanti [\(missing, privacy: .public)]")
                    throw AuthCodeError.generic(Self.debugSuffix(
                        "Registrazione non completata: servono altri dati. Prova con Google o Apple.",
                        "stato \(String(describing: result.status)), mancano [\(missing)]"))
                }
                try await activate(sessionId: sessionId)
            }
            codeAttempt = nil
            setGuest(false)
        } catch {
            throw fail("Verifica codice fallita", error)
        }
    }

    func resendCode() async throws {
        guard let attempt = codeAttempt else { throw AuthCodeError.expired }
        do {
            switch attempt {
            case .signIn(let signIn, let channel):
                let updated = switch channel {
                case .email: try await signIn.sendEmailCode()
                case .phone: try await signIn.sendPhoneCode()
                }
                codeAttempt = .signIn(updated, channel)
            case .signUp(let signUp, let channel):
                let updated = switch channel {
                case .email: try await signUp.sendEmailCode()
                case .phone: try await signUp.sendPhoneCode()
                }
                codeAttempt = .signUp(updated, channel)
            }
        } catch {
            throw fail("Reinvio codice fallito", error)
        }
    }

    func continueAsGuest() {
        setGuest(true)
    }

    func signOut() async throws {
        if Clerk.shared.user != nil {
            try await Clerk.shared.auth.signOut()
        }
        setGuest(false)
    }

    func sessionToken() async throws -> String? {
        try await Clerk.shared.auth.getToken()
    }

    // MARK: - Privato

    /// Esegue il flusso di login; l'annullamento dell'utente esce in silenzio.
    private func perform<T>(_ flow: () async throws -> T) async throws {
        do {
            _ = try await flow()
            setGuest(false)
        } catch where Self.isCancellation(error) {
            Self.log.debug("Login annullato dall'utente")
        } catch {
            Self.log.error("Login fallito: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .auth, step: "oauth")
            throw error
        }
    }

    /// Codici Clerk per "account inesistente" → si passa alla registrazione.
    private static let notFoundCodes: Set<String> = ["form_identifier_not_found", "invitation_account_not_exists"]

    /// Attiva la sessione creata dal codice, se Clerk non l'ha già resa corrente.
    private func activate(sessionId: String) async throws {
        guard Clerk.shared.session?.id != sessionId else { return }
        do {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        } catch {
            // Passo separato per capire dalla diagnostica se fallisce l'attivazione.
            throw fail("Attivazione sessione fallita", error)
        }
    }

    /// Logga e converte l'errore in `AuthCodeError`. In debug l'errore generico porta
    /// anche passo e causa reale (codice Clerk), per diagnosticare dal telefono.
    private func fail(_ what: StaticString, _ error: any Error) -> any Error {
        let mapped = Self.map(error)
        Self.log.error("\(what, privacy: .public): \(Self.describe(error), privacy: .private)")
        // Al report remoto solo gli errori inattesi (codice sbagliato/scaduto sono normali).
        if case .generic? = mapped as? AuthCodeError {
            AppServices.errors.record(error, area: .auth, step: what)
        }
        #if DEBUG
        if !(error is AuthCodeError), case .generic(let message)? = mapped as? AuthCodeError {
            return AuthCodeError.generic("\(message)\n[debug] \(what): \(Self.describe(error))")
        }
        #endif
        return mapped
    }

    /// Dettaglio aggiunto al messaggio solo nelle build di debug.
    private static func debugSuffix(_ message: String, _ detail: String) -> String {
        #if DEBUG
        "\(message)\n[debug] \(detail)"
        #else
        message
        #endif
    }

    private static func describe(_ error: any Error) -> String {
        if let e = error as? ClerkAPIError {
            return "\(e.code) — \(e.longMessage ?? e.message ?? "")"
        }
        return "\(type(of: error)) — \(error.localizedDescription)"
    }

    private static func map(_ error: any Error) -> any Error {
        if error is AuthCodeError || isCancellation(error) { return error }
        if let e = error as? ClerkAPIError {
            switch e.code {
            case "form_code_incorrect":
                return AuthCodeError.wrongCode
            case "verification_expired", "form_code_expired":
                return AuthCodeError.expired
            case "form_param_format_invalid", "form_identifier_invalid", "form_param_nil",
                 "form_param_value_invalid":
                return AuthCodeError.invalidIdentifier
            case "too_many_requests", "rate_limit_exceeded":
                return AuthCodeError.tooManyAttempts
            case "unsupported_country_code":
                return AuthCodeError.unsupportedCountry
            default:
                return AuthCodeError.generic(AppError.generic.message)
            }
        }
        return AuthCodeError.generic(AppError.generic.message)
    }

    private func setGuest(_ value: Bool) {
        isGuest = value
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? ASAuthorizationError, e.code == .canceled { return true }
        if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return true }
        return false
    }
}
