import SwiftUI

extension CodeChannel: Identifiable {
    var id: Self { self }
}

/// Accesso/registrazione senza password con codice monouso (email o SMS).
/// Passo 1: email o numero → invio del codice. Passo 2: inserimento del codice a 6 cifre.
/// Un solo flusso per utenti nuovi ed esistenti; a successo la sheet si chiude e
/// `RootGate` reagisce da solo al cambio di stato.
struct CodeSignInView: View {
    let channel: CodeChannel

    @Environment(\.dismiss) private var dismiss

    private enum Step { case identifier, code }
    private enum Field { case identifier, prefix, code }

    private static let codeLength = 6
    private static let resendDelay = 30

    @State private var step: Step = .identifier
    @State private var email = ""
    @State private var prefix = "+39"
    @State private var number = ""
    @State private var code = ""
    @State private var working = false
    @State private var errorMessage: String?
    /// Secondi che mancano al prossimo "Invia di nuovo".
    @State private var resendRemaining = 0
    /// Cambia a ogni invio: riavvia il conto alla rovescia.
    @State private var countdownID = 0
    @FocusState private var focus: Field?

    var body: some View {
        ZStack {
            CSColor.base.ignoresSafeArea()
            RadialGradient(
                colors: [Rarity.rara.primary.opacity(0.22), .clear],
                center: .top, startRadius: 4, endRadius: 380
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: CSSpace.lg) {
                topBar

                VStack(alignment: .leading, spacing: CSSpace.sm) {
                    Text(step == .identifier ? "Accesso" : "Verifica").eyebrow(Rarity.rara.primary)
                    Text(title)
                        .font(CSFont.display(30))
                        .foregroundStyle(CSColor.ink)
                    Text(subtitle)
                        .font(CSFont.body(15))
                        .foregroundStyle(CSColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Group {
                    switch step {
                    case .identifier: identifierStep
                    case .code: codeStep
                    }
                }
                .disabled(working)
                .animation(.easeOut(duration: 0.2), value: errorMessage)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CSSpace.lg)
            .padding(.top, CSSpace.md)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled(working)
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        // Il focus si imposta solo a campo riabilitato (`working` torna false).
        .onChange(of: working) { _, isWorking in
            if !isWorking && step == .code { focus = .code }
        }
        .task(id: countdownID) {
            while resendRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                resendRemaining -= 1
            }
        }
    }

    // MARK: - Intestazione

    private var topBar: some View {
        HStack {
            if step == .code {
                Button(action: backToIdentifier) {
                    Image(systemName: "chevron.left")
                        .font(CSFont.title(17))
                        .foregroundStyle(CSColor.ink)
                        .frame(minWidth: CSSize.minTap, minHeight: CSSize.minTap)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(channel == .email ? "Cambia email" : "Cambia numero")
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(CSFont.title(15))
                    .foregroundStyle(CSColor.ink)
                    .frame(minWidth: CSSize.minTap, minHeight: CSSize.minTap)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
        }
        .disabled(working)
    }

    private var title: String {
        switch step {
        case .identifier: channel == .email ? "Continua con email" : "Continua con telefono"
        case .code: "Inserisci il codice"
        }
    }

    private var subtitle: String {
        switch step {
        case .identifier:
            "Ti mandiamo un codice di 6 cifre. Niente password."
        case .code:
            "Codice inviato a \(channel == .email ? trimmedEmail : normalizedPhone)."
        }
    }

    // MARK: - Passo 1: email o numero

    private var identifierStep: some View {
        VStack(spacing: CSSpace.md) {
            GlassPanel(cornerRadius: CSRadius.md, padding: CSSpace.md) {
                switch channel {
                case .email:
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .identifier)
                        .submitLabel(.send)
                        .accessibilityLabel("Indirizzo email")
                case .phone:
                    HStack(spacing: CSSpace.sm) {
                        TextField("+39", text: $prefix)
                            .keyboardType(.phonePad)
                            .focused($focus, equals: .prefix)
                            .frame(minWidth: 64)
                            .accessibilityLabel("Prefisso internazionale")
                        Rectangle().fill(CSColor.hairline).frame(width: 1, height: 24)
                        TextField("Numero di telefono", text: $number)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focus, equals: .identifier)
                            .accessibilityLabel("Numero di telefono")
                    }
                }
            }
            .font(CSFont.body(17))
            .foregroundStyle(CSColor.ink)
            .tint(CSColor.accent)
            .frame(minHeight: CSSize.minTap)

            errorText

            PrimaryButton(title: "Invia codice", icon: "paperplane.fill") { sendCode() }
                .disabled(!identifierIsValid)
                .opacity(identifierIsValid ? 1 : 0.4)
                .accessibilityHint("Invia un codice di verifica")
        }
        .onSubmit { if identifierIsValid { sendCode() } }
        .onAppear { focus = .identifier }
    }

    // MARK: - Passo 2: codice

    private var codeStep: some View {
        VStack(spacing: CSSpace.md) {
            GlassPanel(cornerRadius: CSRadius.md, padding: CSSpace.md) {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
                    .multilineTextAlignment(.center)
                    .font(CSFont.numeric(32))
                    .monospacedDigit()
                    .tracking(8)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(CSColor.ink)
                    .tint(CSColor.accent)
                    .accessibilityLabel("Codice di verifica a 6 cifre")
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(Self.codeLength))
                        if digits != new { code = digits; return }
                        if digits.count == Self.codeLength { verify() }
                    }
            }
            .frame(minHeight: CSSize.minTap)

            errorText

            Button(action: resend) {
                Text(resendRemaining > 0 ? "Invia di nuovo tra \(resendRemaining) s" : "Invia di nuovo")
                    .font(CSFont.body(16))
                    .foregroundStyle(resendRemaining > 0 ? CSColor.inkSecondary : CSColor.accent)
                    .frame(maxWidth: .infinity, minHeight: CSSize.minTap)
            }
            .buttonStyle(.plain)
            .disabled(resendRemaining > 0)
            .accessibilityLabel(resendRemaining > 0 ? "Invia di nuovo tra \(resendRemaining) secondi" : "Invia di nuovo")

            GhostButton(title: channel == .email ? "Cambia email" : "Cambia numero", action: backToIdentifier)
        }
        .onAppear { focus = .code }
    }

    /// Errore inline subito sotto il campo.
    @ViewBuilder private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(CSFont.caption(13))
                .foregroundStyle(CSColor.accentWarm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Errore: \(errorMessage)")
                .transition(.opacity)
        }
    }

    // MARK: - Azioni

    private func sendCode() {
        run {
            try await AppServices.auth.startCodeSignIn(channel, identifier: identifier)
            step = .code
            code = ""
            startCountdown()
        }
    }

    private func verify() {
        guard code.count == Self.codeLength, !working else { return }
        run {
            do {
                try await AppServices.auth.verifyCode(code)
            } catch {
                code = ""
                throw error
            }
            if AppServices.auth.state != .signedOut {
                AppServices.analytics.track(.signedIn(method: channel.analyticsMethod))
            }
            dismiss()
        }
    }

    private func resend() {
        run {
            try await AppServices.auth.resendCode()
            code = ""
            startCountdown()
        }
    }

    private func backToIdentifier() {
        errorMessage = nil
        code = ""
        step = .identifier
        focus = .identifier
    }

    private func startCountdown() {
        resendRemaining = Self.resendDelay
        countdownID += 1
    }

    /// Esegue un'azione asincrona con stato di caricamento ed errore inline.
    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await action()
            } catch {
                let message = Self.message(for: error)
                errorMessage = message
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    /// Messaggio dell'auth se c'è, offline per gli errori di rete, altrimenti generico.
    private static func message(for error: any Error) -> String {
        if let authError = error as? AuthCodeError, let text = authError.errorDescription {
            return text
        }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return "Sei offline. Controlla la connessione e riprova."
        }
        return "Qualcosa è andato storto. Riprova."
    }

    // MARK: - Identificatore

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var identifier: String {
        channel == .email ? trimmedEmail : normalizedPhone
    }

    private var identifierIsValid: Bool {
        switch channel {
        case .email:
            let parts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
                && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
                && !trimmedEmail.contains(" ")
        case .phone:
            // E.164: "+" e 8–15 cifre.
            let digits = normalizedPhone.dropFirst()
            return (8...15).contains(digits.count) && digits.allSatisfy(\.isNumber)
        }
    }

    /// Numero in E.164: toglie spazi/trattini/parentesi e aggiunge il prefisso se manca.
    private var normalizedPhone: String {
        let allowed = Set("+0123456789")
        func clean(_ s: String) -> String { String(s.filter { allowed.contains($0) }) }

        var n = clean(number)
        if n.hasPrefix("00") { n = "+" + n.dropFirst(2) }
        if n.hasPrefix("+") { return n }

        var p = clean(prefix)
        if p.hasPrefix("00") { p = "+" + p.dropFirst(2) }
        if !p.hasPrefix("+") { p = "+" + p }
        return p + n
    }
}

#Preview {
    CodeSignInView(channel: .phone)
}
