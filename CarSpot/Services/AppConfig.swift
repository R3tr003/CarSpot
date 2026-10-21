import Foundation

/// Central switchboard for swappable backends. The app stays fully functional
/// offline (mock recognition, local persistence) and connects to Supabase for
/// data/storage once real keys are present in `Secrets.swift`.
enum AppConfig {

    enum RecognitionMode { case mock, remote }

    /// True once `Secrets.swift` contains real Supabase values (not placeholders).
    static var isSupabaseConfigured: Bool {
        !Secrets.supabaseKey.isEmpty
            && !Secrets.supabaseKey.hasPrefix("YOUR-")
            && !Secrets.supabaseURL.contains("YOUR-PROJECT")
    }

    /// Clerk attivo quando c'è una publishable key vera (`pk_test_…`/`pk_live_…`).
    /// Senza, l'app resta in modalità locale (ospite) e il login è simulato.
    static var isClerkConfigured: Bool {
        Secrets.clerkPublishableKey.hasPrefix("pk_")
    }

    /// Mixpanel attivo solo con un token vero; parte comunque spento finché
    /// l'utente non dà il consenso (vedi `Analytics`).
    static var isMixpanelConfigured: Bool {
        !Secrets.mixpanelToken.isEmpty && !Secrets.mixpanelToken.hasPrefix("YOUR-")
    }

    /// Sentry attivo solo con un DSN vero; come Mixpanel parte solo col consenso.
    static var isSentryConfigured: Bool {
        Secrets.sentryDSN.hasPrefix("https://") && Secrets.sentryDSN.contains("@")
    }

    /// Il progetto Mixpanel ha residenza dati EU: i dati verso il server US
    /// verrebbero scartati.
    static let mixpanelServerURL = "https://api-eu.mixpanel.com"

    /// Real vehicle recognition needs a paid provider wired into the `recognize`
    /// Edge Function. Until that's live, keep mock so capture keeps working even
    /// when Supabase is otherwise configured. Flip to `true` when ready.
    static let useRemoteRecognition = false

    static var recognitionMode: RecognitionMode {
        (useRemoteRecognition && isSupabaseConfigured) ? .remote : .mock
    }

    /// Supabase base URL, normalised from whatever was pasted (strips any path
    /// like `/rest/v1/` so endpoints are built correctly).
    static let supabaseURL: URL = {
        let raw = Secrets.supabaseURL
        if let comps = URLComponents(string: raw), let scheme = comps.scheme, let host = comps.host {
            return URL(string: "\(scheme)://\(host)")!
        }
        return URL(string: raw)!
    }()

    /// Publishable key (`sb_publishable_…`) — letto da `Secrets.swift` (gitignored).
    static let supabaseKey = Secrets.supabaseKey

    /// Edge Function that anonymizes-checks and calls the recognition provider.
    static var recognitionEndpoint: URL {
        supabaseURL.appendingPathComponent("functions/v1/recognize")
    }

    /// Builds the active recognition service from configuration.
    static func makeRecognitionService() -> any RecognitionService {
        switch recognitionMode {
        case .mock:   return MockRecognitionService()
        case .remote: return RemoteRecognitionService()
        }
    }
}
