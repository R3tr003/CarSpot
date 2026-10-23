import Foundation
import os
@preconcurrency import Mixpanel

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "analytics")

/// Nome e proprietà (solo non personali) di ogni evento, in snake_case.
/// I nomi esistenti non si cambiano mai: i dati storici restano confrontabili.
extension AnalyticsEvent {
    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .consentGiven: "consent_given"
        case .onboardingCompleted: "onboarding_completed"
        case .signInStarted: "sign_in_started"
        case .signInFailed: "sign_in_failed"
        case .signedIn: "signed_in"
        case .signedOut: "signed_out"
        case .accountDeleted: "account_deleted"
        case .setupStepCompleted: "setup_step_completed"
        case .profileSetupCompleted: "profile_setup_completed"
        case .permissionAnswered: "permission_answered"
        case .tabViewed: "tab_viewed"
        case .panelDetentChanged: "panel_detent_changed"
        case .profileOpened: "profile_opened"
        case .settingsOpened: "settings_opened"
        case .captureStarted: "capture_started"
        case .captureCompleted: "capture_completed"
        case .cardSaved: "card_saved"
        case .cardViewed: "card_viewed"
        case .collectionFiltered: "collection_filtered"
        case .challengeClaimed: "challenge_claimed"
        case .levelUp: "level_up"
        case .realNameUpdated: "real_name_updated"
        case .avatarUpdated: "avatar_updated"
        case .analyticsDisabled: "analytics_disabled"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .onboardingCompleted, .profileSetupCompleted, .signedOut, .accountDeleted,
             .profileOpened, .settingsOpened, .analyticsDisabled:
            [:]
        case .appOpened(let kind): ["kind": .string(kind.rawValue)]
        case .onboardingStepViewed(let step): ["step": .int(step)]
        case .consentGiven(let granted, let origin): ["granted": .bool(granted), "origin": .string(origin)]
        case .signInStarted(let method): ["method": .string(method)]
        case .signInFailed(let method, let reason):
            ["method": .string(method), "reason": .string(reason.rawValue)]
        case .signedIn(let method, let isNewUser):
            if let isNewUser {
                ["method": .string(method), "is_new_user": .bool(isNewUser)]
            } else {
                ["method": .string(method)]
            }
        case .setupStepCompleted(let step): ["step": .string(step.rawValue)]
        case .permissionAnswered(let permission, let granted):
            ["permission": .string(permission.rawValue), "granted": .bool(granted)]
        case .tabViewed(let name): ["name": .string(name)]
        case .panelDetentChanged(let detent): ["detent": .string(detent)]
        case .captureStarted(let source): ["source": .string(source)]
        case .captureCompleted(let outcome, let source, let durationMs, let candidates):
            ["outcome": .string(outcome.rawValue), "source": .string(source),
             "duration_ms": .int(durationMs), "candidates": .int(candidates)]
        case .cardSaved(let rarity, let make, let isFirstCard, let isNewMake, let xpGained):
            ["rarity": .string(rarity), "make": .string(make), "is_first_card": .bool(isFirstCard),
             "is_new_make": .bool(isNewMake), "xp_gained": .int(xpGained)]
        case .cardViewed(let rarity): ["rarity": .string(rarity)]
        case .collectionFiltered(let filter): ["filter": .string(filter)]
        case .challengeClaimed(let id, let reward): ["id": .string(id), "reward": .int(reward)]
        case .levelUp(let level): ["level": .int(level)]
        case .realNameUpdated(let origin): ["origin": .string(origin)]
        case .avatarUpdated(let action): ["action": .string(action)]
        }
    }
}

private extension AnalyticsValue {
    var mixpanelValue: MixpanelType {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
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
    /// Ultimo snapshot ricevuto (anche prima di consenso/identify) e ultimo inviato.
    private var pendingProfile: AnalyticsProfile?
    private var sentProfile: AnalyticsProfile?
    /// Metodo con cui l'utente si è registrato (solo se visto: `is_new_user == true`).
    private var signupMethod: String?

    private static let signupMethodKey = "analyticsSignupMethod"

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
        signupMethod = UserDefaults.standard.string(forKey: Self.signupMethodKey)
        // Mixpanel ricorda l'opt-in tra i lanci: si agisce solo se lo stato diverge
        // (evita di rimandare "$opt_in" a ogni avvio).
        switch consent {
        case .granted where mixpanel.hasOptedOutTracking(): mixpanel.optInTracking()
        case .denied where !mixpanel.hasOptedOutTracking(): mixpanel.optOutTracking()
        default: break
        }
        registerSuperProperties()
    }

    /// Proprietà comuni a ogni evento. Solo versione, lingua e ambiente: nulla di personale.
    /// Si riregistrano a ogni avvio (la lingua può cambiare) e dopo `reset()`, che le azzera.
    private func registerSuperProperties() {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        mixpanel.registerSuperProperties([
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
            "app_language": Locale.app.language.languageCode?.identifier ?? "it",
            "environment": environment,
        ])
    }

    func setConsent(_ newValue: AnalyticsConsent) {
        guard newValue != consent else { return }
        consent = newValue
        AnalyticsConsentStore.save(newValue)
        switch newValue {
        case .granted:
            mixpanel.optInTracking()
            if let id = pendingUserId { mixpanel.identify(distinctId: id) }
            sendProfileIfPossible()
        case .denied:
            // Prima si svuota la coda (compreso `analytics_disabled`), poi si spegne:
            // `optOutTracking` cancella tutto ciò che non è ancora partito.
            mixpanel.flush { [weak self] in
                guard let self, self.consent == .denied else { return }
                self.mixpanel.optOutTracking()
            }
        case .unknown:
            break
        }
        log.info("Consenso analytics: \(newValue.rawValue, privacy: .public)")
    }

    func identify(userId: String) {
        pendingUserId = userId
        guard consent == .granted else { return }
        mixpanel.identify(distinctId: userId)
        sendProfileIfPossible()
    }

    func reset() {
        pendingUserId = nil
        pendingProfile = nil
        sentProfile = nil
        signupMethod = nil
        UserDefaults.standard.removeObject(forKey: Self.signupMethodKey)
        mixpanel.reset()
        registerSuperProperties()
    }

    func track(_ event: AnalyticsEvent) {
        guard consent == .granted else { return }
        if case .signedIn(let method, .some(true)) = event, signupMethod != method {
            signupMethod = method
            UserDefaults.standard.set(method, forKey: Self.signupMethodKey)
        }
        mixpanel.track(event: event.name, properties: event.properties.mapValues(\.mixpanelValue))
    }

    func updateProfile(_ snapshot: AnalyticsProfile) {
        pendingProfile = snapshot
        sendProfileIfPossible()
    }

    /// `people.set` richiede consenso e utente identificato; altrimenti lo snapshot
    /// aspetta in `pendingProfile` e parte dopo `identify`/`setConsent`.
    private func sendProfileIfPossible() {
        guard consent == .granted, pendingUserId != nil, var snapshot = pendingProfile else { return }
        snapshot.signupMethod = signupMethod
        guard snapshot != sentProfile else { return }
        sentProfile = snapshot

        var props: [String: MixpanelType] = [
            "level": snapshot.level,
            "xp": snapshot.xp,
            "cards_count": snapshot.cardsCount,
            "legendary_count": snapshot.legendaryCount,
            "epic_count": snapshot.epicCount,
            "streak_days": snapshot.streakDays,
            "has_real_name": snapshot.hasRealName,
            "app_language": Locale.app.language.languageCode?.identifier ?? "it",
        ]
        if let method = snapshot.signupMethod { props["signup_method"] = method }
        mixpanel.people.set(properties: props)
        if let first = snapshot.firstCaptureAt {
            mixpanel.people.setOnce(properties: ["first_capture_at": first])
        }
    }
}
