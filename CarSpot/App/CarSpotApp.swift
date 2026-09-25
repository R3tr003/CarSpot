import SwiftUI
import SwiftData

@main
struct CarSpotApp: App {
    let container: ModelContainer

    init() {
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
