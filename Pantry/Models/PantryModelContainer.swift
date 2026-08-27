import Foundation
import SwiftData

/// Builds the app's SwiftData stack.
///
/// The schema is declared in one place so tests, previews and the widget snapshot code
/// all agree on it. If the persistent store cannot be opened we fall back to an
/// in-memory store rather than crashing on launch — the user keeps a working app and
/// sees a clear message instead of a dead icon.
enum PantryModelContainer {

    static let schema = Schema([
        PantryItem.self,
        Recipe.self,
        RecipeIngredient.self,
        ShoppingItem.self,
        MealPlanEntry.self,
        CookingSession.self,
        UserPreferences.self
    ])

    /// Set when the on-disk store could not be opened, so the UI can say so.
    private(set) static var didFallBackToMemory = false

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            didFallBackToMemory = true
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                // An in-memory container failing means the schema itself is invalid,
                // which is a programmer error rather than a runtime condition.
                fatalError("Unable to create the Pantry data store: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches the single preferences record, creating it on first launch.
    static func preferences(in context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let preferences = UserPreferences()
        context.insert(preferences)
        try? context.save()
        return preferences
    }
}
