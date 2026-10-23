import Foundation

/// Come è stata aperta l'app: base per la retention.
enum AnalyticsOpenKind: String, Sendable {
    case cold, warm
}

/// Perché un accesso è fallito. Valori enumerati: mai il messaggio d'errore.
enum AnalyticsSignInFailure: String, Sendable {
    case wrongCode = "wrong_code"
    case expired
    case unsupportedCountry = "unsupported_country"
    case cancelled
    case other
}

/// Passi del setup profilo (nello stesso ordine in cui si completano).
enum AnalyticsSetupStep: String, Sendable {
    case welcome, realName = "real_name", username, permissions, photo
}

enum AnalyticsPermission: String, Sendable {
    case camera, location
}

/// Esito della pipeline di cattura (l'annullamento non è un esito: non si traccia).
enum AnalyticsCaptureOutcome: String, Sendable {
    case success, noVehicle = "no_vehicle", unreadable
    case recognitionFailed = "recognition_failed", offline, error
}

/// Eventi di prodotto tipizzati: niente stringhe sparse nelle view.
/// Proprietà solo non personali (mai email, nome, foto, coordinate, testo libero,
/// messaggi d'errore). Nomi e proprietà sono in `MixpanelAnalytics.swift`; il piano
/// completo è in `docs/analytics/tracking-plan.md`.
enum AnalyticsEvent: Sendable {
    // Ciclo di vita e onboarding
    case appOpened(kind: AnalyticsOpenKind)
    case onboardingStepViewed(step: Int)  // non visibile: il consenso arriva dopo (vedi tracking plan)
    case consentGiven(granted: Bool, origin: String)  // origin: "onboarding" | "settings"; si traccia solo se concesso
    case onboardingCompleted
    // Accesso
    case signInStarted(method: String)    // "apple" | "google" | "email" | "phone"
    case signInFailed(method: String, reason: AnalyticsSignInFailure)
    case signedIn(method: String, isNewUser: Bool?)  // nil = il provider non lo distingue
    case signedOut
    case accountDeleted
    // Setup profilo
    case setupStepCompleted(step: AnalyticsSetupStep)
    case profileSetupCompleted
    case permissionAnswered(permission: AnalyticsPermission, granted: Bool)
    // Navigazione
    case tabViewed(name: String)          // "today" | "collection" | "map" | "capture"
    case panelDetentChanged(detent: String)  // "small" | "medium" | "large"
    case profileOpened
    case settingsOpened
    // Cattura e collezione
    case captureStarted(source: String)   // "camera" | "library" | "auto"
    case captureCompleted(outcome: AnalyticsCaptureOutcome, source: String, durationMs: Int, candidates: Int)
    case cardSaved(rarity: String, make: String, isFirstCard: Bool, isNewMake: Bool, xpGained: Int)
    case cardViewed(rarity: String)
    case collectionFiltered(filter: String)  // "all" o valore di `Rarity`
    // Gioco
    case challengeClaimed(id: String, reward: Int)
    case levelUp(level: Int)
    // Profilo e privacy
    case realNameUpdated(origin: String)  // "setup" | "settings"
    case avatarUpdated(action: String)    // "set" | "removed"
    case analyticsDisabled
}

/// Valore di una proprietà evento: solo tipi semplici, mai oggetti.
enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
}

/// Foto istantanea dello stato del giocatore per il profilo utente Mixpanel.
/// Solo contatori e flag: mai il nome, né altri dati personali.
struct AnalyticsProfile: Sendable, Equatable {
    var level: Int
    var xp: Int
    var cardsCount: Int
    var legendaryCount: Int
    var epicCount: Int
    var streakDays: Int
    var hasRealName: Bool
    /// Data della prima carta (`setOnce`): nil se non ce ne sono.
    var firstCaptureAt: Date?
    /// Come si è registrato l'utente; lo riempie il servizio, non il chiamante.
    var signupMethod: String?
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
    /// Aggiorna il profilo utente (livello, contatori…). Parte solo con consenso e
    /// utente identificato; altrimenti resta in attesa. Ignora gli snapshot invariati.
    func updateProfile(_ snapshot: AnalyticsProfile)
}
