import SwiftUI
import SwiftData
import ClerkKit

@main
struct CarSpotApp: App {
    let container: ModelContainer
    /// Sync cloud; senza Supabase+Clerk configurati è spento (`store == nil`).
    let sync: SyncService

    init() {
        // Report crash prima di tutto il resto, ma solo col consenso statistiche.
        AppServices.errors.apply(consent: AnalyticsConsentStore.load())
        // Metriche di ciclo di vita (avvio, primo piano, permessi, stato del dispositivo).
        AppTelemetry.shared.start()
        // Clerk va configurato una sola volta, e solo con la chiave vera (senza,
        // l'app usa l'auth locale e non tocca Clerk).
        if AppConfig.isClerkConfigured {
            Clerk.configure(publishableKey: Secrets.clerkPublishableKey)
        }
        do {
            container = try ModelContainer(for: StoredCard.self, PlayerProfile.self)
        } catch {
            fatalError("Impossibile creare il ModelContainer: \(error)")
        }
        let store = SupabaseBackend.shared.map { SupabaseCloudStore(client: $0.client) }
        sync = SyncService(container: container, store: store)
        SyncService.shared = sync
    }

    var body: some Scene {
        WindowGroup {
            RootGate()
                .preferredColorScheme(.dark)
                .tint(CSColor.accent)
                .environment(sync)
                .task {
                    _ = PlayerStore.profile(container.mainContext)
                    PlayerStore.reportProgress(container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
