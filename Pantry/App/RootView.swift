import SwiftUI
import SwiftData

/// The app's top level.
///
/// A native `TabView` — five real areas, each owning its own navigation state. On iPad
/// the same tabs become a sidebar via `.sidebarAdaptable`, so the structure the user
/// learned on iPhone is the structure they see on a larger screen.
struct RootView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreferences]
    @Query private var items: [PantryItem]
    @Query(filter: #Predicate<ShoppingItem> { !$0.isPurchased }) private var shoppingItems: [ShoppingItem]

    var body: some View {
        @Bindable var appEnvironment = appEnvironment

        TabView(selection: $appEnvironment.selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbolName, value: AppTab.home) {
                HomeView()
            }
            Tab(AppTab.pantry.title, systemImage: AppTab.pantry.symbolName, value: AppTab.pantry) {
                PantryView()
            }
            Tab(AppTab.recipes.title, systemImage: AppTab.recipes.symbolName, value: AppTab.recipes) {
                RecipesView()
            }
            Tab(AppTab.shopping.title, systemImage: AppTab.shopping.symbolName, value: AppTab.shopping) {
                ShoppingView()
            }
            Tab(AppTab.more.title, systemImage: AppTab.more.symbolName, value: AppTab.more) {
                MoreView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            // First launch: put the bundled recipe library in place so the Recipes tab
            // has content with no network and no account.
            RecipeLibrary.installIfNeeded(context: modelContext)
            refreshPreferenceSnapshot()
            refreshWidgetSnapshot()
            await appEnvironment.notifications.refreshAuthorizationStatus()
        }
        .onChange(of: preferences.first?.lastUpdated) { _, _ in
            refreshPreferenceSnapshot()
            refreshWidgetSnapshot()
        }
        .onChange(of: items.count) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: shoppingItems.count) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: scenePhase) { _, phase in
            // Catches edits that don't change a count — a quantity, a date, a cook.
            if phase == .background { refreshWidgetSnapshot() }
        }
        .onOpenURL { url in
            if let route = DeepLink.route(for: url) {
                appEnvironment.route(to: route)
            }
        }
    }

    private func refreshPreferenceSnapshot() {
        let record = PantryModelContainer.preferences(in: modelContext)
        appEnvironment.preferences = PreferenceSnapshot(record)
    }

    private func refreshWidgetSnapshot() {
        WidgetSnapshotBuilder.refresh(context: modelContext, preferences: appEnvironment.preferences)
    }
}

/// Turns `pantry://` URLs from widgets and notifications into routes.
enum DeepLink {
    static let scheme = "pantry"

    static func route(for url: URL) -> AppRoute? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "what-can-i-make": return .whatCanIMake
        case "use-soon": return .useSoon
        case "add": return .addItem
        case "quick-add": return .quickAdd
        case "shopping": return .shoppingList
        case "recipe":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return .recipe(id)
        default: return nil
        }
    }

    static func url(for route: AppRoute) -> URL? {
        switch route {
        case .whatCanIMake: return URL(string: "\(scheme)://what-can-i-make")
        case .useSoon: return URL(string: "\(scheme)://use-soon")
        case .addItem: return URL(string: "\(scheme)://add")
        case .quickAdd: return URL(string: "\(scheme)://quick-add")
        case .shoppingList: return URL(string: "\(scheme)://shopping")
        case .recipe(let id): return URL(string: "\(scheme)://recipe/\(id.uuidString)")
        case .pantryItem(let id): return URL(string: "\(scheme)://item/\(id.uuidString)")
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
