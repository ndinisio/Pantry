import AppIntents
import SwiftData
import Foundation

/// The actions Pantry exposes to Siri, Spotlight and the Shortcuts app.
///
/// Each one is something a person would genuinely say out loud with their hands full,
/// and each returns a spoken answer rather than only opening the app.
struct PantryShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatCanIMakeIntent(),
            phrases: [
                "What can I make with \(.applicationName)",
                "What can I cook with \(.applicationName)",
                "Ask \(.applicationName) what to cook"
            ],
            shortTitle: "What Can I Make?",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ShowExpiringItemsIntent(),
            phrases: [
                "What needs using in \(.applicationName)",
                "What's expiring in \(.applicationName)"
            ],
            shortTitle: "What Needs Using",
            systemImageName: "clock.badge"
        )
        AppShortcut(
            intent: AddPantryItemIntent(),
            phrases: [
                "Add to my \(.applicationName)",
                "Add an item to \(.applicationName)"
            ],
            shortTitle: "Add to Pantry",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my \(.applicationName) shopping list",
                "Put something on my \(.applicationName) list"
            ],
            shortTitle: "Add to Shopping List",
            systemImageName: "cart.badge.plus"
        )
    }
}

/// Shared access to the app's store from an intent, which runs outside the SwiftUI
/// environment and so has to build its own container.
@MainActor
enum IntentStore {
    private static var container: ModelContainer = PantryModelContainer.makeContainer()

    static var context: ModelContext { container.mainContext }

    static var preferences: PreferenceSnapshot {
        PreferenceSnapshot(PantryModelContainer.preferences(in: context))
    }

    static func items() -> [PantryItem] {
        (try? context.fetch(FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    static func recipes() -> [Recipe] {
        (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
    }

    static func refreshWidgets() {
        WidgetSnapshotBuilder.refresh(context: context, preferences: preferences)
    }
}
