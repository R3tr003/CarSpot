import Foundation

/// Istanze condivise dei servizi con dipendenze esterne. Le factory scelgono
/// l'implementazione reale o locale in base ad `AppConfig` (vedi `AuthFactory.swift`
/// `AnalyticsFactory.swift` e `ErrorReportingFactory.swift`).
@MainActor
enum AppServices {
    static let auth: any AuthService = makeAuthService()
    static let analytics: any AnalyticsService = makeAnalyticsService()
    /// Non isolato: gli errori si registrano anche fuori dal main actor.
    nonisolated static let errors: any ErrorReporting = makeErrorReporter()
}
