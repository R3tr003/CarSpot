import SwiftUI

/// App shell: the native iOS 26 `TabView` (authentic Liquid Glass tab bar) over a
/// single persistent map background. The map is the TabView's `.background`, so
/// it's mounted once — switching tabs never reloads it or moves the camera.
struct RootShellView: View {
    @State private var selection: Screen = Self.initialScreen
    @State private var mapHost = MapHost()
    @State private var location = LocationManager()
    @State private var showProfile = false

    enum Screen: Hashable {
        case today, collection, capture, territory

        /// Nome stabile per le statistiche.
        var analyticsName: String {
            switch self {
            case .today: "today"
            case .collection: "collection"
            case .capture: "capture"
            case .territory: "map"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Oggi", systemImage: "sun.max.fill", value: .today) {
                SheetCard { TodayView() }
            }
            Tab("Collezione", systemImage: "square.grid.2x2.fill", value: .collection) {
                SheetCard { CollectionView() }
            }
            Tab("Mappa", systemImage: "map.fill", value: .territory) {
                SheetCard { TerritoryView() }
            }
            Tab("Cattura", systemImage: "camera.viewfinder", value: .capture, role: .search) {
                CaptureView()
            }
        }
        .background {
            PersistentMapView(host: mapHost).ignoresSafeArea()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(CSColor.accent)
        .environment(\.openProfile) { showProfile = true }
        .task { location.request() }
        .onChange(of: selection, initial: true) { _, screen in
            AppServices.analytics.track(.tabViewed(name: screen.analyticsName))
        }
        .sheet(isPresented: $showProfile) {
            ZStack {
                AsphaltBackground(tint: Rarity.leggendaria.primary)
                ProfileView()
            }
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }

    /// Debug: `-startTab` keeps working for screenshots.
    private static var initialScreen: Screen {
        switch UserDefaults.standard.string(forKey: "startTab") {
        case "collection": return .collection
        case "capture": return .capture
        case "map", "territory": return .territory
        default: return .today
        }
    }
}

#Preview {
    RootShellView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
