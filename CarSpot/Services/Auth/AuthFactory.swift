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
    private static let firstNameKey = "localPersonFirst"
    private static let lastNameKey = "localPersonLast"

    private(set) var state: AuthState
    let isReady = true
    /// L'auth simulata non distingue registrazione e accesso.
    var lastSignInIsNewUser: Bool? { nil }
    private(set) var personName: PersonName?

    init() {
        let d = UserDefaults.standard
        // L'ospite non è più persistito: il vecchio "guest" (e il flag `isSignedIn`) → login.
        state = d.string(forKey: Self.key) == "signed" ? .signedIn(userId: "local-user") : .signedOut
        personName = PersonName(first: d.string(forKey: Self.firstNameKey),
                                last: d.string(forKey: Self.lastNameKey))
    }

    func signInWithApple() async throws { set(.signedIn(userId: "local-user")) }
    func signInWithGoogle() async throws { set(.signedIn(userId: "local-user")) }

    /// Simulazione del codice: accetta solo `simulatedCode`.
    private static let simulatedCode = "424242"
    private var pendingChannel: CodeChannel?

    func startCodeSignIn(_ channel: CodeChannel, identifier: String) async throws {
        guard !identifier.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AuthCodeError.invalidIdentifier
        }
        try? await Task.sleep(for: .milliseconds(400))
        pendingChannel = channel
    }

    func verifyCode(_ code: String) async throws {
        guard pendingChannel != nil else { throw AuthCodeError.expired }
        try? await Task.sleep(for: .milliseconds(400))
        guard code == Self.simulatedCode else { throw AuthCodeError.wrongCode }
        pendingChannel = nil
        set(.signedIn(userId: "local-user"))
    }

    func resendCode() async throws {
        guard pendingChannel != nil else { throw AuthCodeError.expired }
        try? await Task.sleep(for: .milliseconds(300))
    }

    func continueAsGuest() { set(.guest) }
    func signOut() async throws {
        set(.signedOut)
        personName = nil
        UserDefaults.standard.removeObject(forKey: Self.firstNameKey)
        UserDefaults.standard.removeObject(forKey: Self.lastNameKey)
    }
    func deleteAccount() async throws { try await signOut() }
    var accountImageURL: URL? { nil }
    func sessionToken() async throws -> String? { nil }

    func updatePersonName(first: String, last: String) async throws {
        let name = PersonName(first: first, last: last)
        personName = name
        UserDefaults.standard.set(name?.first, forKey: Self.firstNameKey)
        UserDefaults.standard.set(name?.last, forKey: Self.lastNameKey)
    }

    private func set(_ new: AuthState) {
        state = new
        let raw: String? = switch new {
        case .signedOut, .guest: nil   // ospite solo in memoria (debug)
        case .signedIn:          "signed"
        }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }
}
