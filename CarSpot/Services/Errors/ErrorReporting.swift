import Foundation
import UIKit
import ClerkKit
import Supabase

/// Area dell'app in cui nasce l'errore: prima parte del raggruppamento (fingerprint).
enum ErrorArea: String, Sendable {
    case auth, profile, sync, capture, recognition, camera, vision
    /// Solo prove manuali in DEBUG (`-sentryTest`).
    case debug
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
    /// Misura una operazione async (monitoring prestazioni). Implementazione vera di
    /// `measure`: i chiamanti usano l'estensione qui sotto, che passa l'isolation.
    func trace<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        isolation: isolated (any Actor)?,
        _ body: () async throws -> T
    ) async rethrows -> T
    /// Come `trace` ma per codice sincrono (es. salvataggio SwiftData sul main actor).
    func measureSync<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        _ body: () throws -> T
    ) rethrows -> T
    /// Log strutturato per eventi operativi (es. "sync completed"). Mai dati dell'utente.
    func log(_ message: StaticString, level: TelemetryLogLevel, attributes: TelemetryAttributes)
    /// Contatore (es. cattura avviata). `value` = quanti eventi.
    func metric(count name: StaticString, value: UInt, attributes: TelemetryAttributes)
    /// Distribuzione di un valore (durate, confidenze): percentili in dashboard.
    func metric(distribution name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes)
    /// Valore puntuale che sale e scende (code, dimensioni).
    func metric(gauge name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes)
    /// Esclude la view dalle registrazioni di sessione (Session Replay): nel replay al suo
    /// posto c'è un riquadro nero. Per anteprima fotocamera e mappa. No-op se spento.
    @MainActor func maskInReplays(_ view: UIView)
}

/// Gravità di un log operativo.
enum TelemetryLogLevel: Sendable { case info, warning, error }

/// Unità di una metrica (solo quelle usate).
enum TelemetryUnit: Sendable { case millisecond, second }

/// Valore semplice di un attributo di log/metrica. Solo letterali o valori enumerati:
/// mai testo libero, email, nomi, targhe o coordinate.
enum TelemetryValue: Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool)
}

extension TelemetryValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                          ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

typealias TelemetryAttributes = [String: TelemetryValue]

extension Duration {
    /// Millisecondi (con decimali), per le metriche di durata.
    var telemetryMilliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

extension ErrorReporting {
    func log(_ message: StaticString, level: TelemetryLogLevel = .info, attributes: TelemetryAttributes = [:]) {
        log(message, level: level, attributes: attributes)
    }

    func metric(count name: StaticString, value: UInt = 1, attributes: TelemetryAttributes = [:]) {
        metric(count: name, value: value, attributes: attributes)
    }

    func metric(distribution name: StaticString, value: Double, unit: TelemetryUnit? = nil,
                attributes: TelemetryAttributes = [:]) {
        metric(distribution: name, value: value, unit: unit, attributes: attributes)
    }

    func metric(gauge name: StaticString, value: Double, unit: TelemetryUnit? = nil,
                attributes: TelemetryAttributes = [:]) {
        metric(gauge: name, value: value, unit: unit, attributes: attributes)
    }
}

extension ErrorReporting {
    /// Misura durata ed esito di un'operazione: transazione se non ce n'è una in corso
    /// (della catena corrente), altrimenti span figlio. Il corpo gira nell'isolation del
    /// chiamante. `name` e `operation` sono `StaticString`: mai dati utente.
    func measure<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await trace(name, operation: operation, isolation: isolation, body)
    }
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
