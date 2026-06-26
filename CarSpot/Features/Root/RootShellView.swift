import SwiftUI

/// App shell: the native iOS 26 `TabView` (authentic Liquid Glass tab bar) over a
/// persistent map background. Content screens sit in a `SheetCard` so the map
/// shows above them; the Capture tab is full-bleed for the camera.
struct RootShellView: View {
    @State private var selection: Screen = Self.initialScreen
    @State private var mapPosition = MapBackground.defaultPosition

    enum Screen: Hashable { case today, collection, capture, territory, profile }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Oggi", systemImage: "sun.max.fill", value: .today) {
                mapped { TodayView() }
            }
            Tab("Collezione", systemImage: "square.grid.2x2.fill", value: .collection) {
                mapped { CollectionView() }
            }
            Tab("Cattura", systemImage: "camera.viewfinder", value: .capture, role: .search) {
                CaptureView()
            }
            Tab("Mappa", systemImage: "map.fill", value: .territory) {
                mapped { TerritoryView() }
            }
            Tab("Profilo", systemImage: "person.fill", value: .profile) {
                mapped { ProfileView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(CSColor.accent)
    }

    /// Wraps a screen above the shared map background, inside a bottom card.
    private func mapped<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            MapBackground(position: $mapPosition).ignoresSafeArea()
            SheetCard { content() }
        }
    }

    /// Debug: `-startTab` keeps working for screenshots.
    private static var initialScreen: Screen {
        switch UserDefaults.standard.string(forKey: "startTab") {
        case "collection": return .collection
        case "capture": return .capture
        case "map", "territory": return .territory
        case "profile": return .profile
        default: return .today
        }
    }
}

#Preview {
    RootShellView()
        .preferredColorScheme(.dark)
        .modelContainer(for: StoredCard.self, inMemory: true)
}
