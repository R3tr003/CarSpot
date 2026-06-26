import Foundation

/// Central switchboard for swappable backends. Defaults keep the app fully
/// functional offline (mock recognition, local persistence) so it runs on the
/// simulator without any keys. Flip to `.remote` once the Supabase project and
/// recognition Edge Function are deployed.
enum AppConfig {

    enum RecognitionMode { case mock, remote }

    /// Recognition source. `.mock` returns plausible local candidates.
    static let recognitionMode: RecognitionMode = .mock

    /// Supabase project URL — letto da `Secrets.swift` (gitignored).
    static let supabaseURL = URL(string: Secrets.supabaseURL)!

    /// Public anon key — letto da `Secrets.swift` (gitignored).
    static let supabaseAnonKey = Secrets.supabaseAnonKey

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
