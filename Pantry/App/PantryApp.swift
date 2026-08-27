import SwiftUI
import SwiftData
import TipKit

@main
struct PantryApp: App {

    /// One container for the whole app, created once at launch.
    private let container: ModelContainer
    @State private var appEnvironment = AppEnvironment()

    init() {
        container = PantryModelContainer.makeContainer()
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
        }
        .modelContainer(container)
    }
}
