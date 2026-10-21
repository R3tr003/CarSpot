import Foundation

/// Messaggio d'errore per l'utente, unico per tutta l'app: breve, in italiano, mai
/// dettagli tecnici. Le view mostrano `message`; la diagnostica va a `ErrorReporting`.
enum AppError: LocalizedError, Equatable, Sendable {
    case offline
    case signInFailed
    case photoUnreadable
    case captureFailed
    case noVehicleFound
    case recognitionFailed
    case saveCardFailed
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
        } else if let e = error as? RecognitionError {
            self = e.appError
        } else if let e = error as? any UserFacingError, let text = e.errorDescription {
            self = .custom(text)
        } else {
            self = fallback
        }
    }

    /// Messaggio da mostrare. In DEBUG, se l'errore non era previsto (si ricade sul
    /// `fallback`), aggiunge tipo e codice per diagnosticare dal telefono: mai in release.
    static func message(for error: any Error, fallback: AppError = .generic) -> String {
        let mapped = AppError(error, fallback: fallback)
        #if DEBUG
        if mapped == fallback, !(error is AppError) {
            let summary = ErrorSummary(error)
            return "\(mapped.message)\n[debug] \(summary.type) \(summary.code)"
        }
        #endif
        return mapped.message
    }

    var message: String {
        switch self {
        case .offline: "Sei offline. Controlla la connessione e riprova."
        case .signInFailed: "Accesso non riuscito. Riprova."
        case .photoUnreadable: "Non sono riuscito a leggere la foto. Riprova."
        case .captureFailed: "Scatto non riuscito. Riprova."
        case .noVehicleFound: "Nessuna auto riconosciuta. Inquadra l'auto di 3/4 e riprova."
        case .recognitionFailed: "Non sono riuscito a riconoscere l'auto. Riprova."
        case .saveCardFailed: "Non sono riuscito a salvare la carta. Riprova."
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

private extension RecognitionError {
    /// Il testo di `.network` è tecnico: per l'utente solo i messaggi di `AppError`.
    var appError: AppError {
        switch self {
        case .noMatch: .noVehicleFound
        case .network: .recognitionFailed
        }
    }
}
