import Foundation
import AuthenticationServices
import ClerkKit
import os

/// Auth reale via Clerk. Solo con `AppConfig.isClerkConfigured` (Clerk va configurato in
/// `CarSpotApp.init`: toccare `Clerk.shared` prima assert in debug).
/// `state` legge `Clerk.shared.user` (osservabile): le view si aggiornano da sole.
@MainActor
@Observable
final class ClerkAuthService: AuthService {
    /// Chiave dell'ex modalità ospite persistita: oggi viene solo rimossa all'avvio.
    private static let legacyGuestKey = "clerkGuestMode"
    private static let log = Logger(subsystem: "com.carspot.andrea.app", category: "auth")

    /// Ospite solo in memoria (debug `-skipAuth`). Stored property per essere osservata.
    private var isGuest = false

    init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyGuestKey)
    }

    var state: AuthState {
        if let user = Clerk.shared.user { return .signedIn(userId: user.id) }
        return isGuest ? .guest : .signedOut
    }

    var isReady: Bool { Clerk.shared.isLoaded }

    func signInWithApple() async throws {
        try await perform { try await Clerk.shared.auth.signInWithApple() }
    }

    func signInWithGoogle() async throws {
        try await perform { try await Clerk.shared.auth.signInWithOAuth(provider: .google) }
    }

    func continueAsGuest() {
        setGuest(true)
    }

    func signOut() async throws {
        if Clerk.shared.user != nil {
            try await Clerk.shared.auth.signOut()
        }
        setGuest(false)
    }

    func sessionToken() async throws -> String? {
        try await Clerk.shared.auth.getToken()
    }

    // MARK: - Privato

    /// Esegue il flusso di login; l'annullamento dell'utente esce in silenzio.
    private func perform<T>(_ flow: () async throws -> T) async throws {
        do {
            _ = try await flow()
            setGuest(false)
        } catch where Self.isCancellation(error) {
            Self.log.debug("Login annullato dall'utente")
        } catch {
            Self.log.error("Login fallito: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func setGuest(_ value: Bool) {
        isGuest = value
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? ASAuthorizationError, e.code == .canceled { return true }
        if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return true }
        return false
    }
}
