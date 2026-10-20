import Foundation

extension AppServices {
    static func makeAuthService() -> any AuthService {
        AppConfig.isClerkConfigured ? ClerkAuthService() : LocalAuthService()
    }
}

/// Auth locale (nessuna chiave Clerk): login simulato, stato persistito in UserDefaults.
@MainActor
@Observable
final class LocalAuthService: AuthService {
    private static let key = "localAuthState"

    private(set) var state: AuthState
    let isReady = true

    init() {
        let d = UserDefaults.standard
        switch d.string(forKey: Self.key) {
        case "guest":  state = .guest
        case "signed": state = .signedIn(userId: "local-user")
        default:
            // Migrazione: il vecchio flag `isSignedIn` (login simulato) diventa ospite.
            state = d.bool(forKey: "isSignedIn") ? .guest : .signedOut
        }
    }

    func signInWithApple() async throws { set(.signedIn(userId: "local-user")) }
    func signInWithGoogle() async throws { set(.signedIn(userId: "local-user")) }
    func continueAsGuest() { set(.guest) }
    func signOut() async throws { set(.signedOut) }
    func sessionToken() async throws -> String? { nil }

    private func set(_ new: AuthState) {
        state = new
        let raw: String? = switch new {
        case .signedOut: nil
        case .guest:     "guest"
        case .signedIn:  "signed"
        }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }
}
