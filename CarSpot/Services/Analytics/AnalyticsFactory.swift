import Foundation

extension AppServices {
    static func makeAnalyticsService() -> any AnalyticsService {
        AppConfig.isMixpanelConfigured ? MixpanelAnalytics() : NoopAnalytics()
    }
}

/// Persistenza del consenso (condivisa da Mixpanel e No-op, così la UI si comporta uguale).
enum AnalyticsConsentStore {
    static let key = "analyticsConsent"

    static func load() -> AnalyticsConsent {
        UserDefaults.standard.string(forKey: key).flatMap(AnalyticsConsent.init(rawValue:)) ?? .unknown
    }

    /// Lo stesso consenso vale per il report errori/crash (Sentry): un punto solo.
    @MainActor static func save(_ consent: AnalyticsConsent) {
        UserDefaults.standard.set(consent.rawValue, forKey: key)
        AppServices.errors.apply(consent: consent)
    }
}

/// Analytics spenta (nessun token Mixpanel): registra solo il consenso.
@MainActor
final class NoopAnalytics: AnalyticsService {
    private(set) var consent: AnalyticsConsent = AnalyticsConsentStore.load()
    func setConsent(_ consent: AnalyticsConsent) {
        self.consent = consent
        AnalyticsConsentStore.save(consent)
    }
    func identify(userId: String) {}
    func reset() {}
    func track(_ event: AnalyticsEvent) {}
}
