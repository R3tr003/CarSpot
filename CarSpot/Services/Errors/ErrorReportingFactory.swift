import Foundation

extension AppServices {
    nonisolated static func makeErrorReporter() -> any ErrorReporting {
        AppConfig.isSentryConfigured ? SentryErrorReporter() : NoopErrorReporter()
    }
}

/// Report errori spento (nessun DSN Sentry): restano solo i log `os.Logger` locali.
struct NoopErrorReporter: ErrorReporting {
    @MainActor func apply(consent: AnalyticsConsent) {}
    func setUser(id: String?) {}
    func record(_ error: any Error, area: ErrorArea, step: StaticString) {}
    func breadcrumb(_ message: StaticString, area: ErrorArea) {}
}
