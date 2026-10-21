import Foundation
import ClerkKit
import Supabase

/// Area dell'app in cui nasce l'errore: prima parte del raggruppamento (fingerprint).
enum ErrorArea: String, Sendable {
    case auth, profile, sync, capture, recognition, camera, vision
}

/// Report di errori e crash dal campo dietro protocollo: Sentry (EU) quando c'è il DSN,
/// altrimenti no-op. Parte solo col consenso statistiche (lo stesso di Mixpanel).
/// `Sendable` e non isolato: si chiama da qualsiasi contesto (anche la coda della camera).
///
/// Privacy: `step` e `message` sono `StaticString` apposta, così non ci finiscono mai
/// dati dell'utente; dell'errore viaggiano solo tipo e codice (`ErrorSummary`).
protocol ErrorReporting: Sendable {
    /// `.granted` avvia la raccolta, altrimenti la spegne.
    @MainActor func apply(consent: AnalyticsConsent)
    /// Solo l'id Clerk ("user_…"), nient'altro. `nil` al logout.
    func setUser(id: String?)
    /// Errore inatteso non fatale. Annullamenti ignorati, problemi di rete solo come traccia.
    func record(_ error: any Error, area: ErrorArea, step: StaticString)
    /// Traccia leggera che accompagna i prossimi errori/crash.
    func breadcrumb(_ message: StaticString, area: ErrorArea)
}

/// Riassunto di un errore senza dati personali: tipo e codice stabili, usati per il
/// raggruppamento. Mai `localizedDescription` o valori associati (possono contenere
/// email, numeri di telefono, nomi utente).
struct ErrorSummary: Sendable, Equatable {
    let type: String
    let code: String
    let isConnectivity: Bool
    let isCancellation: Bool

    init(_ error: any Error) {
        var connectivity = false
        var cancellation = error is CancellationError
        switch error {
        case let e as ClerkAPIError:
            type = "ClerkAPIError"; code = e.code
        case let e as PostgrestError:
            type = "PostgrestError"; code = e.code ?? "unknown"
        case let e as URLError:
            type = "URLError"; code = String(e.code.rawValue)
            connectivity = Self.connectivityCodes.contains(e.code)
            cancellation = e.code == .cancelled
        case let e as AuthCodeError:
            type = "AuthCodeError"; code = e.caseName
        case let e as RecognitionError:
            type = "RecognitionError"
            switch e {
            case .noMatch: code = "noMatch"
            case .network: code = "network"
            }
        case let e as ProfileAccountError:
            type = "ProfileAccountError"; code = String(describing: e)
        case let e as CameraError:
            type = "CameraError"; code = String(describing: e)
        default:
            // Errori di sistema/SDK: dominio e codice NSError, mai il messaggio.
            let ns = error as NSError
            type = String(describing: Swift.type(of: error))
            code = "\(ns.domain)#\(ns.code)"
            connectivity = ns.domain == NSURLErrorDomain
                && Self.connectivityCodes.contains(URLError.Code(rawValue: ns.code))
        }
        isConnectivity = connectivity
        isCancellation = cancellation
    }

    /// Offline, rete persa o lenta: capita sul campo, non è un bug da raggruppare.
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]
}

private extension AuthCodeError {
    /// Nome del caso senza il messaggio associato.
    var caseName: String {
        switch self {
        case .wrongCode: "wrongCode"
        case .expired: "expired"
        case .invalidIdentifier: "invalidIdentifier"
        case .tooManyAttempts: "tooManyAttempts"
        case .unsupportedCountry: "unsupportedCountry"
        case .generic: "generic"
        }
    }
}
