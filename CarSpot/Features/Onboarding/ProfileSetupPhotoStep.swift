import SwiftUI

/// Passo 4 · foto profilo (facoltativa): libreria o fotocamera, ritaglio circolare.
/// Con Google la foto dell'account può essere già stata importata da sola.
struct ProfileSetupPhotoStep: View {
    let account: ProfileAccount
    var errorMessage: String?

    @State private var showPicker = false
    /// Errore del salvataggio della foto (locale al passo; non blocca mai).
    @State private var photoError: String?

    private var hasPhoto: Bool { account.avatar != nil }

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 4 DI 5",
            title: "La tua foto",
            subtitle: "Così gli altri spotter ti riconoscono in classifica. Puoi cambiarla quando vuoi dal profilo."
        ) {
            VStack(spacing: CSSpace.lg) {
                UserAvatar(size: 140, name: account.username, avatar: account.avatar)
                    .overlay {
                        if account.isAvatarBusy {
                            ZStack {
                                Circle().fill(CSColor.base.opacity(0.55))
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(CSColor.ink)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hasPhoto ? "Foto profilo" : "Nessuna foto profilo")
                    .accessibilityValue(account.isAvatarBusy ? "In corso" : "")

                GhostButton(title: hasPhoto ? "Cambia foto" : "Scegli una foto", icon: "photo.on.rectangle") {
                    showPicker = true
                }
                .disabled(account.isAvatarBusy)
                .opacity(account.isAvatarBusy ? 0.4 : 1)

                if let message = photoError ?? errorMessage {
                    Text(message)
                        .font(CSFont.caption(13))
                        .foregroundStyle(CSColor.accentWarm)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .avatarPicker(isPresented: $showPicker, hasPhoto: hasPhoto, onPicked: save, onRemove: remove)
    }

    private func save(_ jpeg: Data) {
        photoError = nil
        Task {
            do {
                try await account.setAvatar(jpeg: jpeg)
            } catch {
                photoError = AppError.shown(for: error, fallback: .saveAvatarFailed)
            }
        }
    }

    private func remove() {
        photoError = nil
        Task {
            do {
                try await account.removeAvatar()
            } catch {
                photoError = AppError.shown(for: error, fallback: .saveAvatarFailed)
            }
        }
    }
}
