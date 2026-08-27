import Foundation
import Observation
import SwiftUI

/// The app's dependencies in one injectable object.
///
/// Views read services from here rather than constructing them, which keeps them
/// testable and means a preview or a test can hand in a different `AIService` without
/// touching a single view.
@Observable
final class AppEnvironment {

    /// The AI stack. Rebuilt when the developer toggles sample responses.
    private(set) var aiService: AIService
    let network: NetworkMonitor
    let notifications: NotificationService

    /// A plain-value copy of preferences, refreshed whenever they change, so services
    /// never need a `ModelContext`.
    var preferences: PreferenceSnapshot = .default

    /// Where the app should navigate next, set by App Intents, widgets and notifications.
    var pendingRoute: AppRoute?
    var selectedTab: AppTab = .home

    /// Set when the persistent store could not be opened, so the UI can be honest
    /// about the fact that this session will not be saved.
    let isUsingTemporaryStore: Bool

    init(
        aiService: AIService? = nil,
        notifications: NotificationService? = nil,
        isUsingTemporaryStore: Bool = PantryModelContainer.didFallBackToMemory
    ) {
        let useSamples = UserDefaults.standard.bool(forKey: DeveloperSettings.sampleAIResponsesKey)
        self.aiService = aiService ?? AIService.makeDefault(includeSampleProvider: useSamples)
        self.network = NetworkMonitor()
        self.notifications = notifications ?? NotificationService()
        self.isUsingTemporaryStore = isUsingTemporaryStore
    }

    /// Rebuilds the provider chain after a settings change.
    func reloadAIConfiguration() {
        let useSamples = UserDefaults.standard.bool(forKey: DeveloperSettings.sampleAIResponsesKey)
        aiService = AIService.makeDefault(includeSampleProvider: useSamples)
    }

    func route(to route: AppRoute) {
        selectedTab = route.tab
        pendingRoute = route
    }

    /// Consumes a pending route, so a destination handles it exactly once.
    func takePendingRoute(matching predicate: (AppRoute) -> Bool) -> AppRoute? {
        guard let pendingRoute, predicate(pendingRoute) else { return nil }
        self.pendingRoute = nil
        return pendingRoute
    }
}

/// Keys for the small number of settings that are genuinely app-level rather than
/// user data, so they belong in `UserDefaults` rather than SwiftData.
enum DeveloperSettings {
    static let sampleAIResponsesKey = "developer.sampleAIResponses"
    static let hasSeenWelcomeKey = "app.hasSeenWelcome"
}
