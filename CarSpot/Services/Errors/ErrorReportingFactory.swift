import Foundation
import UIKit

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

    func log(_ message: StaticString, level: TelemetryLogLevel, attributes: TelemetryAttributes) {}
    func metric(count name: StaticString, value: UInt, attributes: TelemetryAttributes) {}
    func metric(distribution name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes) {}
    func metric(gauge name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes) {}
    @MainActor func maskInReplays(_ view: UIView) {}

    func trace<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        isolation: isolated (any Actor)?,
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await body()
    }

    func measureSync<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        _ body: () throws -> T
    ) rethrows -> T {
        try body()
    }
}
