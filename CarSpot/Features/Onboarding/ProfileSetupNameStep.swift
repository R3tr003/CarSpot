import SwiftUI

/// Stato del campo "nome da spotter": filtra mentre si digita e verifica la
/// disponibilità con debounce.
@MainActor
@Observable
final class UsernameChecker {
    enum Status: Equatable {
        case unchanged, invalid, checking, available, taken
        /// Rete assente: si lascia continuare, il vincolo `unique` decide al salvataggio.
        case unverified
    }

    var text: String {
        didSet {
            let clean = ProfileAccount.sanitize(text)
            if clean != text { text = clean }
        }
    }
    private(set) var original: String
    private(set) var status: Status

    init(current: String) {
        let clean = ProfileAccount.sanitize(current)
        text = clean
        original = clean
        status = ProfileAccount.isValid(clean) ? .unchanged : .invalid
    }

    var canContinue: Bool {
        switch status {
        case .unchanged, .available, .unverified: true
        case .invalid, .checking, .taken: false
        }
    }

    /// Da chiamare in un `.task(id: text)`: la cancellazione al cambio di testo fa il debounce.
    func validate(using account: ProfileAccount) async {
        let value = text
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

/// Passo 1 · scelta del nome da spotter.
struct ProfileSetupNameStep: View {
    let account: ProfileAccount
    @Bindable var checker: UsernameChecker
    var focused: FocusState<Bool>.Binding
    var errorMessage: String?

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 1 DI 3",
            title: "Come ti chiami in strada?",
            subtitle: "È il nome che vedono gli altri spotter nelle classifiche."
        ) {
            VStack(spacing: CSSpace.sm) {
                field
                hint
                if let errorMessage {
                    Text(errorMessage)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var field: some View {
        HStack(spacing: CSSpace.xs) {
            Text("@")
                .font(CSFont.title(20))
                .foregroundStyle(CSColor.inkTertiary)
                .accessibilityHidden(true)
            TextField("", text: $checker.text, prompt: Text("nome_spotter").foregroundStyle(CSColor.inkTertiary))
                .font(CSFont.title(20))
                .foregroundStyle(CSColor.ink)
                .tint(CSColor.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
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
        switch checker.status {
        case .invalid:
            hintRow("exclamationmark.circle.fill", "3–20 caratteri: lettere minuscole, numeri, punto o trattino basso", CSColor.accentWarm)
        case .checking:
            HStack(spacing: CSSpace.xs) {
                ProgressView().controlSize(.small).tint(CSColor.inkSecondary)
                Text("Controllo…").font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
            }
            .frame(minHeight: 20)
        case .available:
            hintRow("checkmark.circle.fill", "Disponibile", CSColor.accent)
        case .taken:
            hintRow("xmark.circle.fill", "Già preso", CSColor.accentWarm)
        case .unverified:
            hintRow("wifi.slash", "Non riesco a verificarlo ora: lo controlliamo al salvataggio", CSColor.inkSecondary)
        case .unchanged:
            Color.clear.frame(height: 20)
        }
    }

    private func hintRow(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CSSpace.xs) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(text).font(CSFont.caption(13)).multilineTextAlignment(.leading)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
