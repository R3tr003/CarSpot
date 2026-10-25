import SwiftUI

/// Una voce dell'action sheet. `role: .destructive` la colora di rosso.
struct CSSheetAction: Identifiable {
    let id = UUID()
    var title: LocalizedStringKey
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    var action: () -> Void
}

extension View {
    /// Action sheet che sale dal fondo (pannello di sistema alto quanto il contenuto),
    /// al posto del `confirmationDialog` di iOS 26 che si apre a fumetto con la freccia.
    /// L'azione scelta parte solo a pannello chiuso: può presentarne un altro (libreria,
    /// fotocamera) senza scontrarsi con la chiusura in corso.
    func csActionSheet(
        _ title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        isPresented: Binding<Bool>,
        actions: [CSSheetAction]
    ) -> some View {
        modifier(CSActionSheetModifier(title: title, message: message,
                                       isPresented: isPresented, actions: actions))
    }
}

private struct CSActionSheetModifier: ViewModifier {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    @Binding var isPresented: Bool
    let actions: [CSSheetAction]

    /// Azione scelta, eseguita in `onDismiss`.
    @State private var pending: (() -> Void)?
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: runPending) {
            CSActionSheetContent(title: title, message: message, actions: actions) { action in
                pending = action
                isPresented = false
            } onCancel: {
                isPresented = false
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(CSColor.surface)
            .preferredColorScheme(.dark)
        }
    }

    private func runPending() {
        let action = pending
        pending = nil
        action?()
    }
}

private struct CSActionSheetContent: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actions: [CSSheetAction]
    let onSelect: (@escaping () -> Void) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: CSSpace.md) {
            VStack(spacing: CSSpace.xxs) {
                Text(title)
                    .font(CSFont.title(17))
                    .foregroundStyle(CSColor.ink)
                if let message {
                    Text(message)
                        .font(CSFont.caption())
                        .foregroundStyle(CSColor.inkSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, CSSpace.md)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(actions) { item in
                    if item.id != actions.first?.id {
                        Rectangle().fill(CSColor.hairline).frame(height: 1)
                    }
                    row(item.title, systemImage: item.systemImage, role: item.role) {
                        onSelect(item.action)
                    }
                }
            }
            .background(CSColor.elevated, in: .rect(cornerRadius: CSRadius.md))

            row("Annulla", systemImage: nil, role: .cancel, action: onCancel)
                .background(CSColor.elevated, in: .rect(cornerRadius: CSRadius.md))
        }
        .padding(.horizontal, CSSpace.md)
        .padding(.top, CSSpace.lg)
        .padding(.bottom, CSSpace.sm)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String?, role: ButtonRole?,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CSSpace.sm) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(role == .cancel ? CSFont.title(17) : CSFont.body(17))
            .foregroundStyle(role == .destructive ? CSColor.danger : (role == .cancel ? CSColor.ink : CSColor.accent))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(CSPressStyle())
    }
}

#Preview {
    Color.black.csActionSheet("Foto profilo", isPresented: .constant(true), actions: [
        CSSheetAction(title: "Scegli dalla libreria", systemImage: "photo.on.rectangle") {},
        CSSheetAction(title: "Scatta una foto", systemImage: "camera") {},
        CSSheetAction(title: "Rimuovi foto", systemImage: "trash", role: .destructive) {}
    ])
}
