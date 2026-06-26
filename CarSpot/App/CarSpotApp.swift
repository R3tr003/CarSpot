import SwiftUI
import SwiftData

@main
struct CarSpotApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: StoredCard.self)
        } catch {
            fatalError("Impossibile creare il ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .preferredColorScheme(.dark)
                .tint(CSColor.accent)
                .task { CardSeeder.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}
