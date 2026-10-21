import SwiftUI
import AVFoundation
import CoreLocation
import os

/// Impostazioni (dal menu dell'avatar): lista nativa raggruppata, come le app di sistema.
/// Account, privacy, permessi, lingua, informazioni ed uscita.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncService.self) private var sync: SyncService?
    @Environment(ProfileAccount.self) private var account: ProfileAccount?

    @State private var consent = AppServices.analytics.consent
    @State private var locationStatus = CLLocationManager().authorizationStatus
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isSigningOut = false
    @State private var showSignOutDialog = false
    /// Elementi non ancora nel cloud trovati al logout (> 0 = chiede conferma).
    @State private var unsyncedCount = 0
    @State private var showUnsyncedAlert = false
    @State private var showSignOutError = false
    @State private var showDeleteDialog = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    private let auth = AppServices.auth
    private var showDeleteError: Binding<Bool> {
        Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                privacySection
                permissionsSection
                generalSection
                if auth.state != .signedOut { signOutSection }
            }
            .scrollContentBackground(.hidden)
            .background(CSColor.base)
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Chiudi")
                }
            }
        }
        .tint(CSColor.accent)
        // Rientrando dalle Impostazioni di sistema i permessi possono essere cambiati.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            locationStatus = CLLocationManager().authorizationStatus
        }
        .confirmationDialog("Vuoi uscire?", isPresented: $showSignOutDialog, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { startSignOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le carte già sincronizzate restano nel cloud: le ritrovi al prossimo accesso.")
        }
        .alert("Dati non sincronizzati", isPresented: $showUnsyncedAlert) {
            Button("Esci comunque", role: .destructive) { signOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            // Singolare/plurale: varianti nel catalogo.
            Text("Hai \(unsyncedCount) elementi non ancora salvati nel cloud. Se esci ora li perdi.")
        }
        .alert("Uscita non riuscita", isPresented: $showSignOutError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Non sono riuscito a uscire. Riprova.")
        }
        .confirmationDialog("Eliminare l'account?", isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button("Elimina account", role: .destructive) { deleteAccount() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le tue carte, le foto e i progressi vengono cancellati per sempre, dal telefono e dal cloud. Non si può annullare.")
        }
        .alert("Eliminazione non riuscita", isPresented: showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    // MARK: - Sezioni

    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: CSSpace.md) {
                UserAvatar(size: 48, name: account?.username ?? "", avatar: account?.avatar)
                VStack(alignment: .leading, spacing: CSSpace.xxs) {
                    Text(auth.personName?.fullName ?? String(localized: "Spotter"))
                        .font(CSFont.title(17))
                        .foregroundStyle(CSColor.ink)
                    if let username = account?.username, !username.isEmpty {
                        Text(verbatim: "@\(username)")
                            .font(CSFont.caption())
                            .foregroundStyle(CSColor.inkSecondary)
                    }
                }
            }
            .padding(.vertical, CSSpace.xxs)
            .accessibilityElement(children: .combine)

            NavigationLink {
                PersonNameEditor()
            } label: {
                LabeledContent("Nome e cognome", value: auth.personName?.fullName ?? "")
            }

            if auth.state != .guest {
                Button(role: .destructive) {
                    showDeleteDialog = true
                } label: {
                    HStack {
                        Text("Elimina account")
                        Spacer()
                        if isDeleting { ProgressView() }
                    }
                }
                .disabled(isDeleting || isSigningOut)
            }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Statistiche anonime", isOn: Binding(
                get: { consent == .granted },
                set: { on in
                    let value: AnalyticsConsent = on ? .granted : .denied
                    // Spegnere le statistiche chiude Sentry: l'evento va prima. Accendendole
                    // Sentry parte solo dopo, quindi l'evento va dopo.
                    if !on { Self.trackAnalyticsToggle(on: false) }
                    AppServices.analytics.setConsent(value)
                    if on { Self.trackAnalyticsToggle(on: true) }
                    consent = value
                }
            ))
        } header: {
            Text("Privacy")
        } footer: {
            Text("Ci dicono come viene usata l'app e ci avvisano degli errori. Mai foto, targhe o posizione.")
        }
    }

    private static func trackAnalyticsToggle(on: Bool) {
        AppServices.errors.metric(count: "settings.toggle",
                                  attributes: ["setting": "analytics", "value": on ? "on" : "off"])
    }

    private var permissionsSection: some View {
        Section {
            permissionRow("Fotocamera", systemImage: "camera.fill", granted: cameraStatus == .authorized,
                          undecided: cameraStatus == .notDetermined)
            permissionRow("Posizione", systemImage: "location.fill",
                          granted: locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways,
                          undecided: locationStatus == .notDetermined)
        } header: {
            Text("Permessi")
        } footer: {
            Text("Si cambiano nelle Impostazioni di iPhone. Della posizione usiamo solo il quartiere.")
        }
    }

    private var generalSection: some View {
        Section("Generali") {
            Button(action: openSystemSettings) {
                LabeledContent("Lingua", value: languageName)
            }
            .foregroundStyle(CSColor.ink)
            LabeledContent("Versione", value: appVersion)
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutDialog = true
            } label: {
                HStack {
                    Text("Esci")
                    Spacer()
                    if isSigningOut { ProgressView() }
                }
            }
            .disabled(isSigningOut || isDeleting)
        }
    }

    // MARK: - Righe

    private func permissionRow(_ title: LocalizedStringKey, systemImage: String,
                               granted: Bool, undecided: Bool) -> some View {
        Button(action: openSystemSettings) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(CSColor.ink)
                Spacer()
                Text(granted ? "Consentito" : (undecided ? "Da chiedere" : "Negato"))
                    .foregroundStyle(granted ? CSColor.inkSecondary : CSColor.accentWarm)
                Image(systemName: "arrow.up.right")
                    .font(CSFont.caption(12))
                    .foregroundStyle(CSColor.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Apre le Impostazioni di iPhone")
    }

    // MARK: - Dati

    /// Lingua in cui gira l'app, nel suo stesso idioma ("Italiano", "English").
    private var languageName: String {
        let locale = Locale.app
        let code = locale.language.languageCode?.identifier ?? "it"
        return locale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// Pagina dell'app nelle Impostazioni di iPhone (permessi e lingua dell'app).
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - Uscita

    /// Dopo la conferma: prima si prova a inviare ciò che è in attesa; se resta qualcosa
    /// si chiede un'ulteriore conferma, altrimenti si esce.
    private func startSignOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        let sync = sync
        Task {
            let left = await sync?.flushPending() ?? 0
            if left > 0 {
                unsyncedCount = left
                showUnsyncedAlert = true
                isSigningOut = false
            } else {
                signOut()
            }
        }
    }

    /// Esce e toglie dal telefono carte e progressi (restano nel cloud).
    /// `signed_out` + reset di analytics li fa RootGate al cambio di stato.
    private func signOut() {
        isSigningOut = true
        let auth = auth
        let sync = sync
        Task {
            defer { isSigningOut = false }
            do {
                try await auth.signOut()
                sync?.signedOutExplicitly()
            } catch {
                Logger(subsystem: "com.carspot.andrea.app", category: "settings")
                    .error("Uscita non riuscita: \(error.localizedDescription, privacy: .public)")
                showSignOutError = true
            }
        }
    }

    // MARK: - Eliminazione account

    /// Elimina l'account (Clerk; il webhook `user.deleted` ripulisce Supabase), poi toglie
    /// i dati locali come all'uscita. Il cambio di stato riporta al login via RootGate.
    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        let auth = auth
        let sync = sync
        Task {
            defer { isDeleting = false }
            do {
                try await auth.deleteAccount()
                sync?.signedOutExplicitly()
            } catch {
                deleteErrorMessage = AppError.shown(
                    for: error,
                    fallback: .custom(String(localized: "Non sono riuscito a eliminare l'account. Riprova.")))
            }
        }
    }
}

/// Modifica di nome e cognome (privati, salvati solo in Clerk).
struct PersonNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var first = AppServices.auth.personName?.first ?? ""
    @State private var last = AppServices.auth.personName?.last ?? ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var trimmedFirst: String { first.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLast: String { last.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedFirst.isEmpty && !trimmedLast.isEmpty && !saving }

    var body: some View {
        List {
            Section {
                TextField("Nome", text: $first)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                TextField("Cognome", text: $last)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(CSColor.accentWarm)
                } else {
                    Text("Resta privato: non lo vedono gli altri spotter.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CSColor.base)
        .navigationTitle("Nome e cognome")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Salva", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                try await AppServices.auth.updatePersonName(first: trimmedFirst, last: trimmedLast)
                AppServices.errors.metric(count: "profile.edit", attributes: ["field": "name", "origin": "settings"])
                dismiss()
            } catch {
                errorMessage = AppError.shown(for: error, fallback: .saveRealNameFailed)
            }
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
