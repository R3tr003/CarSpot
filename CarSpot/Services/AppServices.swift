import Foundation

/// Istanze condivise dei servizi con dipendenze esterne. Le factory scelgono
/// l'implementazione reale o locale in base ad `AppConfig` (vedi `AuthFactory.swift`
/// e `AnalyticsFactory.swift`).
@MainActor
enum AppServices {
    static let auth: any AuthService = makeAuthService()
    static let analytics: any AnalyticsService = makeAnalyticsService()
}
