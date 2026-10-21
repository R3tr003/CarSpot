import Foundation

/// Messaggio d'errore per l'utente, unico per tutta l'app: breve, in italiano, mai
/// dettagli tecnici. Le view mostrano `message`; la diagnostica va a `ErrorReporting`.
enum AppError: LocalizedError, Equatable, Sendable {
    case offline
    case signInFailed
    case photoUnreadable
    case captureFailed
    case recognitionUnavailable
    case saveNameFailed
    case completeSetupFailed
    /// Messaggio già pronto di un errore tipizzato (`UserFacingError`).
    case custom(String)
    case generic

    /// Converte qualsiasi errore: i tipi `UserFacingError` tengono il loro messaggio,
    /// i problemi di rete diventano `.offline`, tutto il resto `fallback`.
    init(_ error: any Error, fallback: AppError = .generic) {
        if let e = error as? AppError {
            self = e
        } else if ErrorSummary(error).isConnectivity {
            self = .offline
        } else if case RecognitionError.network = error {
            self = .recognitionUnavailable
        } else if let e = error as? any UserFacingError, let text = e.errorDescription {
            self = .custom(text)
        } else {
            self = fallback
        }
    }

    var message: String {
        switch self {
        case .offline: "Sei offline. Controlla la connessione e riprova."
        case .signInFailed: "Accesso non riuscito. Riprova tra poco."
        case .photoUnreadable: "Impossibile leggere la foto."
        case .captureFailed: "Scatto non riuscito. Riprova."
        case .recognitionUnavailable: "Riconoscimento non disponibile ora. Riprova tra poco."
        case .saveNameFailed: "Non riesco a salvare il nome. Controlla la connessione e riprova."
        case .completeSetupFailed: "Non riesco a completare ora. Controlla la connessione e riprova."
        case .custom(let text): text
        case .generic: "Qualcosa è andato storto. Riprova."
        }
    }

    var errorDescription: String? { message }
}

/// Errori tipizzati il cui `errorDescription` è già un messaggio per l'utente.
protocol UserFacingError: LocalizedError {}

extension AuthCodeError: UserFacingError {}
extension ProfileAccountError: UserFacingError {}
extension RecognitionError: UserFacingError {}
