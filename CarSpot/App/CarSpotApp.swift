import SwiftUI
import SwiftData
import ClerkKit

@main
struct CarSpotApp: App {
    let container: ModelContainer

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            RootGate()
                .preferredColorScheme(.dark)
                .tint(CSColor.accent)
                .task {
                    CardSeeder.seedIfNeeded(container.mainContext)
                    _ = PlayerStore.profile(container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
