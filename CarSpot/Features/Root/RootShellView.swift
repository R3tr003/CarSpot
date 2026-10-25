import SwiftUI

/// Guscio dell'app stile Flighty: UNA mappa a tutto schermo sotto e sopra un pannello
/// di sistema (`.sheet`) che non si chiude mai, con dentro la `TabView` nativa di
/// iOS 26 (tab bar Liquid Glass autentica, in fondo alla card).
///
/// Il pannello nativo dà gratis quello che il vecchio `SheetCard` rifaceva a mano:
/// trascinamento da qualunque punto, passaggio scroll ↔ pannello, molle di sistema,
/// card flottante con angoli concentrici da piccola/media e a tutta larghezza da alta.
struct RootShellView: View {
    @State private var selection: Screen = Self.initialScreen
    @State private var mapHost = MapHost()
    @State private var location = LocationManager()
    /// Pannello aperto dal menu dell'avatar.
    @State private var accountSheet: AccountSheet?
    @State private var showCapture = Self.startsOnCapture
    @State private var detent: PresentationDetent = Self.mediumDetent

    /// Piccola: solo titolo + tab bar (come Flighty). Media: metà mappa. Alta: sotto l'isola.
    private static let smallDetent = PresentationDetent.height(200)
    private static let mediumDetent = PresentationDetent.fraction(0.5)

    enum AccountSheet: String, Identifiable {
        case profile, settings
        var id: String { rawValue }
    }

    /// Visita di schermata per le dashboard: nomi enumerati e statici.
    private static func trackScreen(_ name: String) {
        AppServices.errors.metric(count: "screen.view", attributes: ["screen": .string(name)])
    }

    /// Altezza del pannello per le dashboard: small | medium | large.
    private static func detentName(_ detent: PresentationDetent) -> String {
        if detent == smallDetent { return "small" }
        if detent == mediumDetent { return "medium" }
        return "large"
    }

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
        // La mappa sta alla radice: niente container UIKit della TabView sopra,
        // quindi riceve tutti i tocchi fuori dal pannello.
        MapSlot(host: mapHost, isActive: true)
            .ignoresSafeArea()
            .task { location.request() }
            .sheet(isPresented: .constant(true)) { panel }
    }

    // MARK: - Pannello

    private var panel: some View {
        TabView(selection: tabSelection) {
            Tab("Oggi", systemImage: "sun.max.fill", value: .today) {
                TodayView()
            }
            Tab("Collezione", systemImage: "square.grid.2x2.fill", value: .collection) {
                CollectionView()
            }
            Tab("Mappa", systemImage: "map.fill", value: .territory) {
                TerritoryView()
            }
            // Il cerchio camera a destra è una tab vera (la cronologia degli scatti); toccarla
            // apre anche la fotocamera a tutto schermo, che non sta in un pannello ridimensionabile.
            Tab("Cattura", systemImage: "camera.viewfinder", value: .capture, role: .search) {
                CaptureHistoryView(onShoot: { showCapture = true }, isCameraPresented: showCapture)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(CSColor.accent)
        .environment(\.openProfile) { accountSheet = .profile }
        .environment(\.openSettings) { accountSheet = .settings }
        .onChange(of: selection, initial: true) { _, screen in
            Self.trackTab(screen)
        }
        .presentationDetents([Self.smallDetent, Self.mediumDetent, .large], selection: $detent)
        .onChange(of: detent) { _, new in
            AppServices.errors.metric(count: "panel.detent", attributes: ["detent": .string(Self.detentName(new))])
            AppServices.analytics.track(.panelDetentChanged(detent: Self.detentName(new)))
        }
        // La mappa resta interattiva a ogni altezza; il pannello non si chiude mai.
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled()
        // Trascinando sul contenuto il pannello prima si ridimensiona, poi scorre.
        .presentationContentInteraction(.resizes)
        .presentationBackground(CSColor.panel)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onChange(of: accountSheet) { _, sheet in
            guard let sheet else { return }
            Self.trackScreen(sheet.rawValue)
            switch sheet {
            case .profile: AppServices.analytics.track(.profileOpened)
            case .settings: AppServices.analytics.track(.settingsOpened)
            }
        }
        .sheet(item: $accountSheet) { sheet in
            Group {
                switch sheet {
                case .profile:
                    ZStack {
                        AsphaltBackground(tint: Rarity.leggendaria.primary)
                        ProfileView()
                    }
                case .settings:
                    SettingsView()
                }
            }
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView()
                .preferredColorScheme(.dark)
        }
    }

    /// Anche la tab Cattura viene selezionata davvero (la TabView UIKit ci resta comunque):
    /// mostra la cronologia, e il tocco apre in più la fotocamera. Chiudendola si resta lì.
    /// Il setter scatta anche se si tocca la tab già selezionata, così la camera si riapre.
    private var tabSelection: Binding<Screen> {
        Binding {
            selection
        } set: { screen in
            selection = screen
            if screen == .capture { showCapture = true }
        }
    }

    private static func trackTab(_ screen: Screen) {
        AppServices.analytics.track(.tabViewed(name: screen.analyticsName))
        trackScreen(screen.analyticsName)
    }

    // MARK: - Debug

    /// `-startTab` continua a funzionare per gli screenshot.
    private static var initialScreen: Screen {
        switch UserDefaults.standard.string(forKey: "startTab") {
        case "collection": return .collection
        case "map", "territory": return .territory
        case "capture": return .capture
        default: return .today
        }
    }

    /// `-startTab capture` apre subito la cattura a tutto schermo (sulla tab Cattura).
    private static var startsOnCapture: Bool {
        UserDefaults.standard.string(forKey: "startTab") == "capture"
    }
}

#Preview {
    RootShellView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}
