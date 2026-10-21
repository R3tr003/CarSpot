import Foundation
import Synchronization
import MapKit
import UIKit
import os
@preconcurrency import Sentry

private let errorsLog = Logger(subsystem: "com.carspot.andrea.app", category: "errors")

/// Sentry (organizzazione con residenza dati EU: lo decide il DSN). Raccoglie crash,
/// blocchi dell'app (hang), chiusure dal watchdog ed errori registrati con `record`,
/// più il monitoring prestazioni (tracing: avvio app, rete, span dei flussi chiave).
/// Spento finché manca il consenso: senza `start` non c'è nemmeno il crash handler.
///
/// Privacy: niente PII di default, niente screenshot né view hierarchy; Session Replay solo
/// con tutto il testo e tutte le immagini mascherati, più anteprima fotocamera e mappa
/// (le foto contengono targhe, la mappa la posizione); URL di eventi, breadcrumb e span
/// ripuliti da query string, fragment e id (utente, sessione, uuid) nel path; niente
/// header di tracing verso terze parti.
final class SentryErrorReporter: ErrorReporting {
    /// Campionamento transazioni: tutto in debug, un quinto in produzione.
    private static let tracesSampleRateDebug: NSNumber = 1.0
    private static let tracesSampleRateRelease: NSNumber = 0.2
    /// Profiling legato alle transazioni: tutte le sessioni in debug, una su dieci in produzione.
    private static let profileSessionSampleRateDebug: Float = 1.0
    private static let profileSessionSampleRateRelease: Float = 0.1
    /// Session Replay: tutte le sessioni in debug (con un errore si invia sempre il buffer
    /// degli ultimi secondi). In produzione SPENTO finché il mascheramento di testo e foto
    /// non è verificato su iOS 26/27 con `-replayMaskPreview YES` (le foto hanno targhe).
    private static let replaySessionSampleRateDebug: Float = 1.0
    private static let replaySessionSampleRateRelease: Float = 0
    private static let replayOnErrorSampleRateDebug: Float = 1.0
    private static let replayOnErrorSampleRateRelease: Float = 0

    /// Span in corso nella catena di task corrente: i `measure` annidati diventano figli.
    /// Non si usa `SentrySDK.span` (globale): potrebbe essere una transazione automatica
    /// di UIKit e i nostri nomi finirebbero dentro quella.
    @TaskLocal private static var currentSpan: SpanBox?

    private struct SpanBox: @unchecked Sendable {
        let span: any Sentry.Span
    }

    /// Id utente arrivato prima del consenso: applicato quando Sentry parte.
    private let userId = Mutex<String?>(nil)

    @MainActor func apply(consent: AnalyticsConsent) {
        switch consent {
        case .granted:
            guard !SentrySDK.isEnabled else { return }
            SentrySDK.start(configureOptions: Self.configure)
            if let id = userId.withLock({ $0 }) { SentrySDK.setUser(User(userId: id)) }
            errorsLog.info("Report errori attivo")
            #if DEBUG
            Self.showReplayMaskPreviewIfRequested()
            #endif
        case .denied, .unknown:
            guard SentrySDK.isEnabled else { return }
            SentrySDK.close()
            errorsLog.info("Report errori spento")
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

    // MARK: - Tracing

    func trace<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        isolation: isolated (any Actor)?,
        _ body: () async throws -> T
    ) async rethrows -> T {
        guard SentrySDK.isEnabled else { return try await body() }
        let span = Self.startSpan(name, operation)
        do {
            let result = try await Self.$currentSpan.withValue(SpanBox(span: span), operation: {
                try await body()
            }, isolation: isolation)
            span.finish(status: .ok)
            return result
        } catch {
            span.finish(status: Self.status(for: error))
            throw error
        }
    }

    func measureSync<T: Sendable>(
        _ name: StaticString, operation: StaticString,
        _ body: () throws -> T
    ) rethrows -> T {
        guard SentrySDK.isEnabled else { return try body() }
        let span = Self.startSpan(name, operation)
        do {
            let result = try Self.$currentSpan.withValue(SpanBox(span: span)) { try body() }
            span.finish(status: .ok)
            return result
        } catch {
            span.finish(status: Self.status(for: error))
            throw error
        }
    }

    /// Figlio dello span corrente, oppure nuova transazione (legata allo scope, così gli
    /// span HTTP automatici dei `URLSession` ci finiscono dentro).
    private static func startSpan(_ name: StaticString, _ operation: StaticString) -> any Sentry.Span {
        if let parent = currentSpan?.span {
            return parent.startChild(operation: "\(operation)", description: "\(name)")
        }
        return SentrySDK.startTransaction(name: "\(name)", operation: "\(operation)", bindToScope: true)
    }

    /// Stato dello span dall'errore, senza leggerne il contenuto: solo tipo/codice.
    private static func status(for error: any Error) -> SentrySpanStatus {
        let summary = ErrorSummary(error)
        if summary.isCancellation { return .cancelled }
        if summary.isConnectivity { return .unavailable }
        // Errori "normali" dell'utente (codice sbagliato, nome preso): non sono guasti.
        if summary.type == "AuthCodeError" || summary.type == "ProfileAccountError" { return .invalidArgument }
        return .internalError
    }

    // MARK: - Log e metriche

    func log(_ message: StaticString, level: TelemetryLogLevel, attributes: TelemetryAttributes) {
        guard SentrySDK.isEnabled else { return }
        let text = "\(message)"
        let values = attributes.mapValues(\.anyValue)
        switch level {
        case .info: SentrySDK.logger.info(text, attributes: values)
        case .warning: SentrySDK.logger.warn(text, attributes: values)
        case .error: SentrySDK.logger.error(text, attributes: values)
        }
    }

    func metric(count name: StaticString, value: UInt, attributes: TelemetryAttributes) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.metrics.count(key: "\(name)", value: value, attributes: attributes.mapValues(\.sentryValue))
    }

    func metric(distribution name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.metrics.distribution(key: "\(name)", value: value, unit: unit?.sentryUnit,
                                       attributes: attributes.mapValues(\.sentryValue))
    }

    func metric(gauge name: StaticString, value: Double, unit: TelemetryUnit?, attributes: TelemetryAttributes) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.metrics.gauge(key: "\(name)", value: value, unit: unit?.sentryUnit,
                                attributes: attributes.mapValues(\.sentryValue))
    }

    @MainActor func maskInReplays(_ view: UIView) {
        // Il contrassegno sta sulla view: vale anche se Sentry parte dopo (consenso tardivo).
        SentrySDK.replay.maskView(view)
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
        // Monitoring prestazioni. Restano attivi i default utili: avvio app, UIViewController,
        // slow/frozen frames, span HTTP di URLSession (`enableAutoPerformanceTracing`,
        // `enableUIViewControllerTracing`, `enableNetworkTracking`) e app hang.
        #if DEBUG
        options.tracesSampleRate = tracesSampleRateDebug
        #else
        options.tracesSampleRate = tracesSampleRateRelease
        #endif
        // Nessun header `sentry-trace`/`baggage` verso Supabase e Clerk (terze parti).
        options.tracePropagationTargets = []
        // Diagnostica di sistema (hang, CPU, scritture disco, crash) da MetricKit, senza payload raw.
        options.enableMetricKit = true
        options.enableMetricKitRawPayload = false
        // Tempi di avvio corretti anche con il pre-warming di iOS.
        options.enablePreWarmedAppStartTracing = true
        // Log strutturati: solo eventi operativi emessi da `log(_:level:attributes:)`.
        options.enableLogs = true
        options.beforeSendLog = scrub(log:)
        // UI profiling: il profilo vive quanto la transazione (`.trace`), quindi segue il
        // campionamento delle transazioni. Niente profilo dell'avvio.
        // Attenzione: il profilo parte solo se è in volo una transazione e viene inviato a
        // blocchi, ogni 60 s (`SentryContinuousProfiler.mm`, `kSentryProfilerChunkExpirationInterval`);
        // se l'app passa in background (anche per un alert di sistema) prima del primo
        // blocco, i campioni non ancora inviati si perdono. Per vedere un profilo l'app
        // deve restare in primo piano almeno un minuto dopo l'inizio di una transazione.
        #if DEBUG
        let profileRate = profileSessionSampleRateDebug
        #else
        let profileRate = profileSessionSampleRateRelease
        #endif
        options.configureProfiling = { profiling in
            profiling.lifecycle = .trace
            profiling.sessionSampleRate = profileRate
            profiling.profileAppStarts = false
        }
        configureSessionReplay(options)
        #if DEBUG
        // Prova manuale: `-sentryDebug YES` stampa nella console di Xcode i log dell'SDK
        // (avvio profiler, invio blocchi di profilo, replay).
        options.debug = UserDefaults.standard.bool(forKey: "sentryDebug")
        #endif
        options.beforeSend = scrub(_:)
        options.beforeBreadcrumb = scrub(_:)
        options.beforeSendSpan = scrub(span:)
    }

    /// Session Replay con privacy massima: testo e immagini sempre mascherati, più le view
    /// che mostrano la fotocamera o la posizione. Niente `unmaskedViewClasses`, niente
    /// dettagli di rete (`networkDetailAllowUrls` resta vuoto).
    ///
    /// iOS 26+ (Liquid Glass): dalla 9.12 l'SDK non spegne più il replay; SwiftUI non
    /// usa più view UIKit per testo e immagini e l'SDK le maschera per nome di layer
    /// (`SentryUIRedactBuilder.registerLiquidGlassLayers`). Resta un punto da verificare a
    /// occhio con `-replayMaskPreview YES` prima di fidarsi dei replay in produzione.
    private static func configureSessionReplay(_ options: Options) {
        let replay = options.sessionReplay
        #if DEBUG
        replay.sessionSampleRate = replaySessionSampleRateDebug
        replay.onErrorSampleRate = replayOnErrorSampleRateDebug
        #else
        replay.sessionSampleRate = replaySessionSampleRateRelease
        replay.onErrorSampleRate = replayOnErrorSampleRateRelease
        #endif
        replay.maskAllText = true
        replay.maskAllImages = true
        // Anteprima fotocamera e mappa (mostra il punto dell'utente): sempre neri, anche
        // se qualcuno crea una nuova istanza senza passare da `maskInReplays`.
        replay.maskedViewClasses = [CameraPreview.PreviewView.self, MKMapView.self]
    }

    #if DEBUG
    /// `-replayMaskPreview YES`: sovrappone all'app i riquadri che il replay maschererà
    /// (solo con il debugger collegato, come lancia Xcode).
    @MainActor private static func showReplayMaskPreviewIfRequested() {
        guard UserDefaults.standard.bool(forKey: "replayMaskPreview") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            SentrySDK.replay.showMaskPreview(0.6)
        }
    }
    #endif

    /// Ultima difesa prima dell'invio: dell'utente resta solo l'id, della richiesta
    /// solo URL senza query, niente header né cookie.
    private static func scrub(_ event: Event) -> Event? {
        if let id = event.user?.userId {
            event.user = User(userId: id)
        } else {
            event.user = nil
        }
        // Nome della transazione: sempre statico, ma per sicurezza niente query né id.
        event.transaction = event.transaction.map(sanitizeURL)
        if let request = event.request {
            request.url = request.url.map(sanitizeURL)
            request.queryString = nil
            request.headers = nil
            request.cookies = nil
            request.bodySize = nil
        }
        return event
    }

    private static func scrub(_ crumb: Breadcrumb) -> Breadcrumb? {
        if let url = crumb.data?["url"] as? String {
            crumb.setData(value: sanitizeURL(url), key: "url")
        }
        return crumb
    }

    /// Log: gli attributi sono solo i nostri (enumerati) più quelli dell'SDK; per sicurezza
    /// via ogni `user.*` tranne l'id e le URL senza query/id.
    private static func scrub(log: SentryLog) -> SentryLog? {
        for (key, attribute) in log.attributes {
            if key.hasPrefix("user."), key != "user.id" {
                log.attributes.removeValue(forKey: key)
            } else if let text = attribute.value as? String, text.contains("://") {
                log.attributes[key] = SentryAttribute(string: sanitizeURL(text))
            }
        }
        return log
    }

    /// Span figli (HTTP automatici inclusi): descrizione e `data` senza query, fragment
    /// né id nel path. Le chiavi `http.query`/`http.fragment` si tolgono del tutto.
    private static func scrub(span: any Sentry.Span) -> (any Sentry.Span)? {
        span.spanDescription = span.spanDescription.map(sanitizeURL)
        span.removeData(key: "http.query")
        span.removeData(key: "http.fragment")
        for (key, value) in span.data {
            guard let text = value as? String, text.contains("://") else { continue }
            span.setData(value: sanitizeURL(text), key: key)
        }
        return span
    }

    /// Le query di Supabase filtrano per valori (es. `username=eq.…`): via query e fragment.
    /// Nel path gli id (utente/sessione Clerk, uuid di carte e foto) diventano `:id`.
    /// Vale anche per stringhe tipo "GET https://host/path?q=1".
    private static func sanitizeURL(_ url: String) -> String {
        let base = url.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? url
        return base.split(separator: "/", omittingEmptySubsequences: false)
            .map { isIdentifier($0) ? ":id" : String($0) }
            .joined(separator: "/")
    }

    /// `user_2abc…`, `sess_…`, `sia_…` (prefisso breve + sottolineatura + 10 o più
    /// alfanumerici) oppure uuid, con eventuale estensione (`<uuid>.jpg`).
    private static func isIdentifier(_ segment: Substring) -> Bool {
        segment.wholeMatch(of: /[a-z]{2,6}_[A-Za-z0-9]{10,}/) != nil
            || segment.wholeMatch(of: /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(\.[A-Za-z0-9]+)?/) != nil
    }
}

private extension TelemetryValue {
    var sentryValue: any SentryAttributeValue {
        switch self {
        case .string(let v): v
        case .int(let v): v
        case .double(let v): v
        case .bool(let v): v
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let v): v
        case .int(let v): v
        case .double(let v): v
        case .bool(let v): v
        }
    }
}

private extension TelemetryUnit {
    var sentryUnit: SentryUnit {
        switch self {
        case .millisecond: .millisecond
        case .second: .second
        }
    }
}
