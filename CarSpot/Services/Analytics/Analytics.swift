import Foundation

/// Eventi di prodotto tipizzati: niente stringhe sparse nelle view.
/// Proprietà solo non personali (mai email, nome, foto, coordinate).
enum AnalyticsEvent: Sendable {
    case onboardingCompleted
    case signedIn(method: String)        // "apple" | "google" | "guest"
    case signedOut
    case tabViewed(name: String)         // "today" | "collection" | "map" | "capture"
    case captureStarted(source: String)  // "camera" | "library" | "auto"
    case cardSaved(rarity: String)       // valore di `Rarity`
    case challengeClaimed(id: String)
}

/// Consenso GDPR alle statistiche: finché non è `.granted` non parte nulla.
enum AnalyticsConsent: String, Sendable {
    case unknown, granted, denied
}

/// Analytics dietro protocollo: Mixpanel quando configurato, altrimenti no-op.
@MainActor
protocol AnalyticsService: AnyObject {
    var consent: AnalyticsConsent { get }
    func setConsent(_ consent: AnalyticsConsent)
    /// Collega gli eventi all'utente Clerk ("user_…"). Solo l'id, nient'altro.
    func identify(userId: String)
    /// Al logout: nuovo distinct id anonimo.
    func reset()
    func track(_ event: AnalyticsEvent)
}
