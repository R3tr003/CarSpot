import Foundation

/// Central switchboard for swappable backends. The app stays fully functional
/// offline (mock recognition, local persistence). It switches to Supabase
/// **automatically** as soon as real keys are present in `Secrets.swift` — no
/// code change needed: just paste your Project URL and anon key there.
enum AppConfig {

    enum RecognitionMode { case mock, remote }

    /// True once `Secrets.swift` contains real Supabase values (not the template
    /// placeholders). When true the app uses the live backend.
    static var isSupabaseConfigured: Bool {
        !Secrets.supabaseKey.isEmpty
            && !Secrets.supabaseKey.hasPrefix("YOUR-")
            && !Secrets.supabaseURL.contains("YOUR-PROJECT")
    }

    /// Recognition source — auto: remote when Supabase is configured, else mock.
    static var recognitionMode: RecognitionMode {
        isSupabaseConfigured ? .remote : .mock
    }

    /// Supabase project URL — letto da `Secrets.swift` (gitignored).
    static let supabaseURL = URL(string: Secrets.supabaseURL)!

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
