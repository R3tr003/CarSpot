import SwiftUI
import AVFoundation
import CoreLocation

/// Passo 2 · permessi spiegati (facoltativi): fotocamera e posizione.
struct ProfileSetupPermissionsStep: View {
    var location: LocationManager

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)

    private enum Access { case undetermined, granted, denied }

    private var cameraAccess: Access {
        switch camera {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .undetermined
        }
    }

    private var locationAccess: Access {
        switch location.status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied, .restricted: .denied
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
                    allow: requestCamera,
                    openSettings: openSettings
                )
                PermissionRow(
                    icon: "location.fill",
                    title: "Posizione",
                    detail: "Per assegnare l'avvistamento al quartiere giusto. La posizione esatta non viene mai mostrata.",
                    access: locationAccess,
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
        var allow: () -> Void
        var openSettings: () -> Void

        var body: some View {
            GlassPanel(cornerRadius: CSRadius.lg) {
                VStack(alignment: .leading, spacing: CSSpace.md) {
                    HStack(spacing: CSSpace.md) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CSColor.accent)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(CSFont.title(18))
                            .foregroundStyle(CSColor.ink)
                        Spacer(minLength: 0)
                        if access == .granted {
                            Label("Consentito", systemImage: "checkmark.circle.fill")
                                .font(CSFont.caption(13))
                                .foregroundStyle(CSColor.accent)
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
                        actionButton("Apri Impostazioni", action: openSettings)
                            .accessibilityLabel("Apri Impostazioni per \(title.lowercased())")
                    case .granted:
                        EmptyView()
                    }
                }
            }
        }

        private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(CSFont.title(15))
                    .foregroundStyle(CSColor.base)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(CSColor.accent, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}
