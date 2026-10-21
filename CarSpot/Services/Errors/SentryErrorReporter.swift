import Foundation
import Synchronization
import os
@preconcurrency import Sentry

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "errors")

/// Sentry (organizzazione con residenza dati EU: lo decide il DSN). Raccoglie crash,
/// blocchi dell'app (hang), chiusure dal watchdog ed errori registrati con `record`.
/// Spento finché manca il consenso: senza `start` non c'è nemmeno il crash handler.
///
/// Privacy: niente PII di default, niente screenshot, view hierarchy o session replay
/// (le foto contengono targhe), query string tolte da URL e breadcrumb di rete.
final class SentryErrorReporter: ErrorReporting {
    /// Id utente arrivato prima del consenso: applicato quando Sentry parte.
    private let userId = Mutex<String?>(nil)

    @MainActor func apply(consent: AnalyticsConsent) {
        switch consent {
        case .granted:
            guard !SentrySDK.isEnabled else { return }
            SentrySDK.start(configureOptions: Self.configure)
            if let id = userId.withLock({ $0 }) { SentrySDK.setUser(User(userId: id)) }
            log.info("Report errori attivo")
        case .denied, .unknown:
            guard SentrySDK.isEnabled else { return }
            SentrySDK.close()
            log.info("Report errori spento")
        }
    }

    func setUser(id: String?) {
        userId.withLock { $0 = id }
        guard SentrySDK.isEnabled else { return }
        SentrySDK.setUser(id.map { User(userId: $0) })
    }

    func record(_ error: any Error, area: ErrorArea, step: StaticString) {
        let summary = ErrorSummary(error)
        guard SentrySDK.isEnabled, !summary.isCancellation else { return }
        if summary.isConnectivity {
            breadcrumb(step, area: area, level: .warning, detail: "\(summary.type) \(summary.code)")
            return
        }
        // Errore "pulito": solo area, passo, tipo e codice. Il fingerprint esplicito
        // raggruppa bene anche senza dSYM caricati.
        let reported = NSError(domain: "\(area.rawValue).\(step)", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "\(summary.type) \(summary.code)",
        ])
        SentrySDK.capture(error: reported) { scope in
            scope.setFingerprint([area.rawValue, "\(step)", summary.type, summary.code])
            scope.setTag(value: area.rawValue, key: "area")
            scope.setTag(value: summary.type, key: "error_type")
            scope.setTag(value: summary.code, key: "error_code")
        }
    }

    func breadcrumb(_ message: StaticString, area: ErrorArea) {
        breadcrumb(message, area: area, level: .info, detail: nil)
    }

    // MARK: - Privato

    private func breadcrumb(_ message: StaticString, area: ErrorArea, level: SentryLevel, detail: String?) {
        guard SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: level, category: area.rawValue)
        crumb.message = detail.map { "\(message): \($0)" } ?? "\(message)"
        SentrySDK.addBreadcrumb(crumb)
    }

    private static func configure(_ options: Options) {
        options.dsn = Secrets.sentryDSN
        #if DEBUG
        options.environment = "development"
        #else
        options.environment = "production"
        #endif
        options.sendDefaultPii = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        // Per ora solo errori e crash (niente tracing/profiling).
        options.tracesSampleRate = nil
        options.beforeSend = scrub(_:)
        options.beforeBreadcrumb = scrub(_:)
    }

    /// Ultima difesa prima dell'invio: dell'utente resta solo l'id, della richiesta
    /// solo URL senza query, niente header né cookie.
    private static func scrub(_ event: Event) -> Event? {
        if let id = event.user?.userId {
            event.user = User(userId: id)
        } else {
            event.user = nil
        }
        if let request = event.request {
            request.url = request.url.map(stripQuery)
            request.queryString = nil
            request.headers = nil
            request.cookies = nil
            request.bodySize = nil
        }
        return event
    }

    private static func scrub(_ crumb: Breadcrumb) -> Breadcrumb? {
        if let url = crumb.data?["url"] as? String {
            crumb.setData(value: stripQuery(url), key: "url")
        }
        return crumb
    }

    /// Le query di Supabase filtrano per valori (es. `username=eq.…`): via.
    private static func stripQuery(_ url: String) -> String {
        url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
    }
}
