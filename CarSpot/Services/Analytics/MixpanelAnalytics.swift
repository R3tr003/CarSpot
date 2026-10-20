import Foundation
import os
@preconcurrency import Mixpanel

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "analytics")

/// Nome e proprietà (solo non personali) di ogni evento, in snake_case.
extension AnalyticsEvent {
    var name: String {
        switch self {
        case .onboardingCompleted: "onboarding_completed"
        case .signedIn: "signed_in"
        case .signedOut: "signed_out"
        case .tabViewed: "tab_viewed"
        case .captureStarted: "capture_started"
        case .cardSaved: "card_saved"
        case .challengeClaimed: "challenge_claimed"
        }
    }

    var properties: [String: String] {
        switch self {
        case .onboardingCompleted, .signedOut: [:]
        case .signedIn(let method): ["method": method]
        case .tabViewed(let name): ["name": name]
        case .captureStarted(let source): ["source": source]
        case .cardSaved(let rarity): ["rarity": rarity]
        case .challengeClaimed(let id): ["id": id]
        }
    }
}

/// Mixpanel (data residency EU) con opt-in GDPR: parte spento e non invia nulla
/// finché l'utente non accetta. Mai posizione, foto, nomi o email.
@MainActor
final class MixpanelAnalytics: AnalyticsService {
    private let mixpanel: MixpanelInstance
    private(set) var consent: AnalyticsConsent
    /// Id utente arrivato prima del consenso: applicato solo se poi viene concesso.
    private var pendingUserId: String?

    init() {
        mixpanel = Mixpanel.initialize(options: MixpanelOptions(
            token: Secrets.mixpanelToken,
            trackAutomaticEvents: false,
            optOutTrackingByDefault: true,
            serverURL: AppConfig.mixpanelServerURL
        ))
        // Non usiamo mai la posizione: niente geolocalizzazione da IP.
        mixpanel.useIPAddressForGeoLocation = false

        consent = AnalyticsConsentStore.load()
        // Mixpanel ricorda l'opt-in tra i lanci: si agisce solo se lo stato diverge
        // (evita di rimandare "$opt_in" a ogni avvio).
        switch consent {
        case .granted where mixpanel.hasOptedOutTracking(): mixpanel.optInTracking()
        case .denied where !mixpanel.hasOptedOutTracking(): mixpanel.optOutTracking()
        default: break
        }
    }

    func setConsent(_ newValue: AnalyticsConsent) {
        guard newValue != consent else { return }
        consent = newValue
        AnalyticsConsentStore.save(newValue)
        switch newValue {
        case .granted:
            mixpanel.optInTracking()
            if let id = pendingUserId { mixpanel.identify(distinctId: id) }
        case .denied:
            mixpanel.optOutTracking()
        case .unknown:
            break
        }
        log.info("Consenso analytics: \(newValue.rawValue, privacy: .public)")
    }

    func identify(userId: String) {
        pendingUserId = userId
        guard consent == .granted else { return }
        mixpanel.identify(distinctId: userId)
    }

    func reset() {
        pendingUserId = nil
        mixpanel.reset()
    }

    func track(_ event: AnalyticsEvent) {
        guard consent == .granted else { return }
        mixpanel.track(event: event.name, properties: event.properties.mapValues { $0 as MixpanelType })
    }
}
