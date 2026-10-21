import SwiftUI
import PhotosUI
import os

private let pickerLog = Logger(subsystem: "com.carspot.andrea.app", category: "avatar")

extension View {
    /// Menu "Foto profilo" (libreria, fotocamera, rimuovi) + ritaglio circolare.
    /// `onPicked` riceve il JPEG già compresso da `AvatarEncoding`.
    func avatarPicker(
        isPresented: Binding<Bool>,
        hasPhoto: Bool,
        onPicked: @escaping (Data) -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        modifier(AvatarPickerModifier(isPresented: isPresented, hasPhoto: hasPhoto,
                                      onPicked: onPicked, onRemove: onRemove))
    }
}

/// Foto scelta in attesa di ritaglio: dati originali + versione orientata da mostrare.
private struct CropRequest: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
}

private struct AvatarPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let hasPhoto: Bool
    let onPicked: (Data) -> Void
    let onRemove: () -> Void

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var selection: PhotosPickerItem?
    @State private var crop: CropRequest?
    @State private var alertMessage: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Foto profilo", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Scegli dalla libreria") { showLibrary = true }
                if cameraAvailable {
                    Button("Scatta una foto") { showCamera = true }
                }
                if hasPhoto {
                    Button("Rimuovi foto", role: .destructive, action: onRemove)
                }
                Button("Annulla", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibrary, selection: $selection, matching: .images)
            .onChange(of: selection) { _, item in
                guard let item else { return }
                selection = nil
                Task { await loadLibraryItem(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    showCamera = false
                    Task { await prepareCrop(from: data) }
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $crop) { request in
                AvatarCropView(
                    image: request.image,
                    onCancel: { crop = nil },
                    onConfirm: { rect in
                        crop = nil
                        Task { await encode(request.data, crop: rect) }
                    }
                )
            }
            .alert("Foto profilo", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
    }

    // MARK: - Flusso

    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                alertMessage = AppError.photoUnreadable.shown()
                return
            }
            await prepareCrop(from: data)
        } catch {
            pickerLog.error("Lettura foto dalla libreria fallita: \(error.localizedDescription, privacy: .public)")
            AppServices.errors.record(error, area: .profile, step: "avatar_library")
            alertMessage = AppError.shown(for: error, fallback: .photoUnreadable)
        }
    }

    /// Decodifica ridotta fuori dal main, poi apre il ritaglio.
    private func prepareCrop(from data: Data) async {
        guard let cg = await AvatarEncoding.displayImage(data: data) else {
            alertMessage = AppError.photoUnreadable.shown()
            return
        }
        // Lascia chiudere il selettore prima di presentare il ritaglio.
        try? await Task.sleep(for: .milliseconds(350))
        crop = CropRequest(data: data, image: UIImage(cgImage: cg))
    }

    private func encode(_ data: Data, crop rect: CGRect) async {
        guard let jpeg = await AvatarEncoding.encode(data: data, crop: rect) else {
            alertMessage = AppError.photoUnreadable.shown()
            return
        }
        onPicked(jpeg)
    }
}

// MARK: - Fotocamera

/// `UIImagePickerController` in modalità fotocamera (frontale se c'è, senza editing).
/// Restituisce il JPEG (qualità 0.9) dell'immagine originale.
private struct CameraPicker: UIViewControllerRepresentable {
    var onData: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onData: onData, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onData: (Data) -> Void
        let onCancel: () -> Void

        init(onData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onData = onData
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }
            onData(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
