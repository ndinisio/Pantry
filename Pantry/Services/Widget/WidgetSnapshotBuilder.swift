import Foundation
import SwiftData

/// Builds the widget snapshot from the live store.
///
/// Called after any change that a widget would show — items added or removed,
/// something cooked, the shopping list edited — rather than on a timer, so the widget
/// reflects reality without polling.
enum WidgetSnapshotBuilder {

    static func refresh(context: ModelContext, preferences: PreferenceSnapshot) {
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let shopping = (try? context.fetch(
            FetchDescriptor<ShoppingItem>(predicate: #Predicate { !$0.isPurchased })
        )) ?? []

        let needingAttention = items
            .filter { $0.quantity > 0 }
            .filter {
                ExpirationCalculator
                    .freshness(for: $0.expirationDate, useSoonWindowDays: preferences.useSoonWindowDays)
                    .isNoteworthy
            }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }

        let best = RecipeMatcher.match(
            recipes: recipes.browsable,
            inventory: items,
            query: RecipeQuery(appetite: .useWhatIHave),
            preferences: preferences,
            useSoonWindowDays: preferences.useSoonWindowDays,
            limit: 1
        ).first

        WidgetSnapshotStore.write(
            WidgetSnapshot(
                totalItems: items.count,
                expiringSoon: needingAttention.count,
                shoppingCount: shopping.count,
                useSoonNames: needingAttention.prefix(3).map(\.name),
                suggestedRecipeTitle: best?.recipe.title,
                suggestedRecipeMinutes: best?.recipe.totalTimeMinutes,
                updatedAt: .now
            )
        )
    }
}
