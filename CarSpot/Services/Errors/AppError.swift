import Foundation

/// Messaggio d'errore per l'utente, unico per tutta l'app: breve, localizzato (italiano/inglese), mai
/// dettagli tecnici. Le view mostrano `message`; la diagnostica va a `ErrorReporting`.
enum AppError: LocalizedError, Equatable, Sendable {
    case offline
    case signInFailed
    case photoUnreadable
    case captureFailed
    case noVehicleFound
    case recognitionFailed
    case recognitionSessionExpired
    case recognitionLimitReached
    /// La foto non è stata usata: non si è riusciti a oscurare volti e targhe.
    case anonymizationFailed
    case saveCardFailed
    case saveNameFailed
    case saveRealNameFailed
    case saveAvatarFailed
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

    /// Come `message(for:fallback:)`, ma conta anche l'errore mostrato (`ui.error`).
    /// Da usare dove il testo finisce a schermo.
    static func shown(for error: any Error, fallback: AppError = .generic) -> String {
        AppError(error, fallback: fallback).countedAsShown()
        return message(for: error, fallback: fallback)
    }

    /// Messaggio di un caso già noto, contato come mostrato (`ui.error`).
    func shown() -> String {
        countedAsShown()
        return message
    }

    private func countedAsShown() {
        AppServices.errors.metric(count: "ui.error", attributes: ["error": .string(caseName)])
    }

    /// Nome del caso per le statistiche: mai il testo, nemmeno quello di `.custom`.
    var caseName: String {
        switch self {
        case .offline: "offline"
        case .signInFailed: "signInFailed"
        case .photoUnreadable: "photoUnreadable"
        case .captureFailed: "captureFailed"
        case .noVehicleFound: "noVehicleFound"
        case .recognitionFailed: "recognitionFailed"
        case .recognitionSessionExpired: "recognitionSessionExpired"
        case .recognitionLimitReached: "recognitionLimitReached"
        case .anonymizationFailed: "anonymizationFailed"
        case .saveCardFailed: "saveCardFailed"
        case .saveNameFailed: "saveNameFailed"
        case .saveRealNameFailed: "saveRealNameFailed"
        case .saveAvatarFailed: "saveAvatarFailed"
        case .completeSetupFailed: "completeSetupFailed"
        case .custom: "custom"
        case .generic: "generic"
        }
    }

    var message: String {
        switch self {
        case .offline: String(localized: "Sei offline. Controlla la connessione e riprova.")
        case .signInFailed: String(localized: "Accesso non riuscito. Riprova.")
        case .photoUnreadable: String(localized: "Non sono riuscito a leggere la foto. Riprova.")
        case .captureFailed: String(localized: "Scatto non riuscito. Riprova.")
        case .noVehicleFound: String(localized: "Nessuna auto riconosciuta. Inquadra l'auto di 3/4 e riprova.")
        case .recognitionFailed: String(localized: "Non sono riuscito a riconoscere l'auto. Riprova.")
        case .recognitionSessionExpired: String(localized: "Sessione scaduta. Accedi di nuovo per riconoscere le auto.")
        case .recognitionLimitReached: String(localized: "Hai raggiunto il limite di riconoscimenti di oggi. Riprova domani.")
        case .anonymizationFailed: String(localized: "Non sono riuscito a proteggere la privacy della foto, quindi non l'ho usata. Riprova o scegli un'altra foto.")
        case .saveCardFailed: String(localized: "Non sono riuscito a salvare la carta. Riprova.")
        case .saveNameFailed: String(localized: "Non riesco a salvare il nome. Controlla la connessione e riprova.")
        case .saveRealNameFailed: String(localized: "Non riesco a salvare nome e cognome. Controlla la connessione e riprova.")
        case .saveAvatarFailed: String(localized: "Non riesco a salvare la foto. Controlla la connessione e riprova.")
        case .completeSetupFailed: String(localized: "Non riesco a completare ora. Controlla la connessione e riprova.")
        case .custom(let text): text
        case .generic: String(localized: "Qualcosa è andato storto. Riprova.")
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
        case .unauthorized: .recognitionSessionExpired
        case .rateLimited: .recognitionLimitReached
        }
    }
}
