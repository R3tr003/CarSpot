import SwiftUI

/// Campo a fuoco nel passo nome e cognome.
enum RealNameField: Hashable {
    case first, last
}

/// Passo 1 · nome e cognome reali. Restano privati e vanno solo in Clerk, mai in Supabase.
struct ProfileSetupRealNameStep: View {
    @Binding var first: String
    @Binding var last: String
    var focused: FocusState<RealNameField?>.Binding
    var errorMessage: String?
    /// Tasto "Continua" della tastiera sul cognome: il flow avanza se si può.
    var onSubmit: () -> Void = {}

    static let maxLength = 50

    /// Entrambi i campi non vuoti dopo il trim (la lunghezza è già limitata mentre si digita).
    static func isValid(first: String, last: String) -> Bool {
        let f = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = last.trimmingCharacters(in: .whitespacesAndNewlines)
        return !f.isEmpty && !l.isEmpty && f.count <= maxLength && l.count <= maxLength
    }

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 1 DI 5",
            title: "Come ti chiami?",
            subtitle: "Resta privato: non lo vedono gli altri spotter."
        ) {
            VStack(spacing: CSSpace.sm) {
                field("Nome", text: $first, field: .first,
                      content: .givenName, submit: .next) { focused.wrappedValue = .last }
                field("Cognome", text: $last, field: .last,
                      content: .familyName, submit: .continue, action: onSubmit)
                if let errorMessage {
                    Text(errorMessage)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func field(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        field: RealNameField,
        content: UITextContentType,
        submit: SubmitLabel,
        action: @escaping () -> Void
    ) -> some View {
        TextField(text: text, prompt: Text(label).foregroundStyle(CSColor.inkTertiary)) { EmptyView() }
            .font(CSFont.title(20))
            .foregroundStyle(CSColor.ink)
            .tint(CSColor.accent)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .textContentType(content)
            .submitLabel(submit)
            .onSubmit(action)
            .focused(focused, equals: field)
            .accessibilityLabel(label)
            .onChange(of: text.wrappedValue) { _, value in
                // Tetto di lunghezza mentre si digita.
                if value.count > Self.maxLength { text.wrappedValue = String(value.prefix(Self.maxLength)) }
            }
            .padding(.horizontal, CSSpace.md)
            .frame(minHeight: 56)
            .glassEffect(.regular, in: .rect(cornerRadius: CSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CSRadius.md, style: .continuous)
                    .strokeBorder(CSColor.hairline, lineWidth: 1.5)
            )
            .contentShape(.rect)
            .onTapGesture { focused.wrappedValue = field }
    }
}
