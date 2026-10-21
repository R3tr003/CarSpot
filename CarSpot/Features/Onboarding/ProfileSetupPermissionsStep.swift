import SwiftUI
import AVFoundation
import CoreLocation

/// Passo 2 · permessi spiegati (facoltativi): fotocamera e posizione.
struct ProfileSetupPermissionsStep: View {
    var location: LocationManager

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)

    private enum Access: Equatable { case undetermined, granted, denied, restricted }

    private var cameraAccess: Access {
        switch camera {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .undetermined
        }
    }

    private var locationAccess: Access {
        switch location.status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .undetermined
        }
    }

    var body: some View {
        ProfileSetupPage(
            eyebrow: "PASSO 2 DI 3",
            title: "Due permessi, spiegati bene",
            subtitle: "Servono per giocare al meglio, ma puoi decidere anche più tardi."
        ) {
            VStack(spacing: CSSpace.md) {
                PermissionRow(
                    icon: "camera.fill",
                    title: "Fotocamera",
                    detail: "Per fotografare le auto e trasformarle in carte. Volti e targhe vengono sfocati sul telefono, prima di qualsiasi invio.",
                    access: cameraAccess,
                    lossNote: "Senza fotocamera non puoi catturare auto.",
                    allow: requestCamera,
                    openSettings: openSettings
                )
                PermissionRow(
                    icon: "location.fill",
                    title: "Posizione",
                    detail: "Per assegnare l'avvistamento al quartiere giusto. La posizione esatta non viene mai mostrata.",
                    access: locationAccess,
                    lossNote: "Senza posizione le carte non mostrano la zona.",
                    allow: { location.request() },
                    openSettings: openSettings
                )
            }
        }
        // Rientro da Impostazioni: rilegge lo stato della fotocamera.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private func requestCamera() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            camera = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private struct PermissionRow: View {
        var icon: String
        var title: String
        var detail: String
        var access: Access
        /// Cosa si perde se il permesso non è concesso.
        var lossNote: String
        var allow: () -> Void
        var openSettings: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GlassPanel(cornerRadius: CSRadius.lg) {
                VStack(alignment: .leading, spacing: CSSpace.md) {
                    HStack(spacing: CSSpace.md) {
                        Image(systemName: icon)
                            .font(CSFont.title(18))
                            .foregroundStyle(CSColor.accent)
                            .frame(minWidth: CSSpace.lg)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(CSFont.title(18))
                            .foregroundStyle(CSColor.ink)
                        Spacer(minLength: 0)
                        if access == .granted {
                            Label("Consentito", systemImage: "checkmark.circle.fill")
                                .font(CSFont.caption(13))
                                .foregroundStyle(CSColor.accent)
                                .transition(.opacity)
                        }
                    }
                    Text(detail)
                        .font(CSFont.body(14))
                        .foregroundStyle(CSColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    switch access {
                    case .undetermined:
                        actionButton("Consenti", action: allow)
                            .accessibilityLabel("Consenti \(title.lowercased())")
                    case .denied:
                        note(lossNote)
                        actionButton("Apri Impostazioni", action: openSettings)
                            .accessibilityLabel("Apri Impostazioni per \(title.lowercased())")
                    case .restricted:
                        // Limitato da controlli del dispositivo: Impostazioni non può cambiarlo.
                        note("\(lossNote) L'accesso è limitato dalle restrizioni di questo dispositivo.")
                    case .granted:
                        EmptyView()
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: access)
            .sensoryFeedback(.success, trigger: access) { _, new in new == .granted }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .font(CSFont.caption(13))
                .foregroundStyle(CSColor.accentWarm)
                .fixedSize(horizontal: false, vertical: true)
        }

        private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(CSFont.title(15))
                    .foregroundStyle(CSColor.inkInverse)
                    .frame(maxWidth: .infinity, minHeight: CSSize.minTap)
                    .background(CSColor.accent, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(CSPressStyle())
        }
    }
}
