import SwiftUI

/// Stato del campo "nome da spotter": filtra mentre si digita e verifica la
/// disponibilità con debounce.
@MainActor
@Observable
final class UsernameChecker {
    enum Status: Equatable {
        /// Campo vuoto: stato neutro, nessun errore prima del primo input.
        case idle
        case unchanged, invalid, checking, available, taken
        /// Rete assente: si lascia continuare, il vincolo `unique` decide al salvataggio.
        case unverified
    }

    var text: String {
        didSet {
            let clean = ProfileAccount.sanitize(text)
            if clean != text {
                // Maiuscole e taglio a 20 non contano: solo spazi e simboli scartati.
                if text.lowercased().contains(where: { ProfileAccount.sanitize(String($0)).isEmpty }) {
                    flagDroppedInput()
                }
                text = clean
            }
        }
    }
    private(set) var original: String
    private(set) var status: Status
    /// `true` per un attimo dopo che sono stati scartati caratteri non ammessi.
    private(set) var droppedInput = false
    @ObservationIgnored private var droppedTask: Task<Void, Never>?

    init(current: String) {
        let clean = ProfileAccount.sanitize(current)
        text = clean
        original = clean
        status = ProfileAccount.isValid(clean) ? .unchanged : (clean.isEmpty ? .idle : .invalid)
    }

    private func flagDroppedInput() {
        droppedInput = true
        droppedTask?.cancel()
        droppedTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { droppedInput = false }
        }
    }

    var canContinue: Bool {
        switch status {
        case .unchanged, .available, .unverified: true
        case .idle, .invalid, .checking, .taken: false
        }
    }

    /// Da chiamare in un `.task(id: text)`: la cancellazione al cambio di testo fa il debounce.
    func validate(using account: ProfileAccount) async {
        let value = text
        if value.isEmpty { status = .idle; return }
        guard ProfileAccount.isValid(value) else { status = .invalid; return }
        if value == original { status = .unchanged; return }
        status = .checking
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        do {
            let free = try await account.isUsernameAvailable(value)
            if Task.isCancelled { return }
            status = free ? .available : .taken
        } catch {
            if Task.isCancelled { return }
            status = .unverified
        }
    }

    func markSaved() {
        original = text
        status = .unchanged
    }

    func markTaken() { status = .taken }
}

/// Passo 2 · scelta del nome da spotter.
struct ProfileSetupNameStep: View {
    let account: ProfileAccount
    @Bindable var checker: UsernameChecker
    var focused: FocusState<Bool>.Binding
    var errorMessage: String?
    /// Tasto "Continua" della tastiera: il flow avanza se si può.
    var onSubmit: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Altezza minima dell'area hint (due righe): niente salti al cambio di stato.
    @ScaledMetric private var hintMinHeight: CGFloat = 40

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 2 DI 5",
            title: "Come ti chiami in strada?",
            subtitle: "È il nome che vedono gli altri spotter nelle classifiche."
        ) {
            VStack(spacing: CSSpace.sm) {
                field
                hint
                    .frame(maxWidth: .infinity, minHeight: hintMinHeight, alignment: .top)
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: checker.status)
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: checker.droppedInput)
                if let errorMessage {
                    Text(errorMessage)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                }
            }
        }
        // Annunci VoiceOver per i cambi di stato (il testo dell'hint cambia senza focus).
        .onChange(of: checker.status) { _, status in
            if let text = announcement(for: status) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
        .onChange(of: checker.droppedInput) { _, dropped in
            if dropped { AccessibilityNotification.Announcement(String(localized: Self.droppedMessage)).post() }
        }
    }

    private static let droppedMessage: LocalizedStringResource = "Spazi e simboli non sono ammessi"
    private static let rulesMessage: LocalizedStringResource = "3–20 caratteri: lettere minuscole, numeri, _ e ."

    private func announcement(for status: UsernameChecker.Status) -> String? {
        switch status {
        case .checking: String(localized: "Controllo disponibilità")
        case .available: String(localized: "Nome disponibile")
        case .taken: String(localized: "Nome già preso")
        case .unverified: String(localized: "Non riesco a verificare il nome ora")
        default: nil
        }
    }

    private var field: some View {
        HStack(spacing: CSSpace.xs) {
            Text("@")
                .font(CSFont.title(20))
                .foregroundStyle(CSColor.inkTertiary)
                .accessibilityHidden(true)
            TextField(text: $checker.text, prompt: Text("nome_spotter").foregroundStyle(CSColor.inkTertiary)) { EmptyView() }
                .font(CSFont.title(20))
                .foregroundStyle(CSColor.ink)
                .tint(CSColor.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.nickname)
                .submitLabel(.continue)
                .onSubmit(onSubmit)
                .focused(focused)
                .accessibilityLabel("Nome da spotter")
        }
        .padding(.horizontal, CSSpace.md)
        .frame(minHeight: 56)
        .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CSRadius.md, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .contentShape(.rect)
        .onTapGesture { focused.wrappedValue = true }
        .task(id: checker.text) { await checker.validate(using: account) }
    }

    private var borderColor: Color {
        switch checker.status {
        case .available: CSColor.accent
        case .invalid, .taken: CSColor.accentWarm
        default: CSColor.hairline
        }
    }

    @ViewBuilder
    private var hint: some View {
        if checker.droppedInput {
            hintRow("exclamationmark.circle.fill", Self.droppedMessage, CSColor.accentWarm)
        } else {
            statusHint
        }
    }

    @ViewBuilder
    private var statusHint: some View {
        switch checker.status {
        case .idle:
            hintRow("info.circle", Self.rulesMessage, CSColor.inkSecondary)
        case .invalid:
            hintRow("exclamationmark.circle.fill", Self.rulesMessage, CSColor.accentWarm)
        case .checking:
            HStack(spacing: CSSpace.xs) {
                ProgressView().controlSize(.small).tint(CSColor.inkSecondary)
                Text("Controllo…").font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        case .available:
            hintRow("checkmark.circle.fill", "Disponibile", CSColor.accent)
        case .taken:
            hintRow("xmark.circle.fill", takenMessage, CSColor.accentWarm)
        case .unverified:
            hintRow("wifi.slash", "Non riesco a verificarlo ora: lo controlliamo al salvataggio", CSColor.inkSecondary)
        case .unchanged:
            Color.clear.frame(height: 1)
        }
    }

    /// "Già preso", con un'alternativa solo se resta un nome valido (≤ 20 caratteri).
    private var takenMessage: LocalizedStringResource {
        let alternative = "\(checker.text)_2"
        return ProfileAccount.isValid(alternative) ? "Già preso. Prova \(alternative)" : "Già preso"
    }

    private func hintRow(_ icon: String, _ text: LocalizedStringResource, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CSSpace.xs) {
            Image(systemName: icon).font(CSFont.caption(13))
            Text(text).font(CSFont.caption(13)).multilineTextAlignment(.leading)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
