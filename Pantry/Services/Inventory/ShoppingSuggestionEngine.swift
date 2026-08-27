import Foundation

/// A proposed purchase, with the reasoning attached.
///
/// The reason is the point: a shopping list that just says "chicken breast" is a list,
/// while one that says "would unlock 8 recipes you can otherwise almost make" is advice.
struct ShoppingSuggestion: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var category: FoodCategory
    var quantity: Double
    var unit: MeasurementUnit
    var priority: ShoppingPriority
    var reason: String
    var sourceRecipeTitle: String?
    /// How many additional recipes this single purchase would make cookable.
    var recipesUnlocked: Int = 0

    func makeShoppingItem() -> ShoppingItem {
        ShoppingItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            priority: priority,
            reason: reason,
            isSuggested: true,
            sourceRecipeTitle: sourceRecipeTitle
        )
    }
}

/// Works out what is worth buying, reasoning from the pantry the user actually has.
enum ShoppingSuggestionEngine {

    /// - Parameters:
    ///   - plannedRecipes: recipes on the meal plan. Their missing ingredients are "needed".
    ///   - existingListKeys: normalised names already on the shopping list, so nothing is proposed twice.
    static func suggestions(
        inventory: [PantryItem],
        recipes: [Recipe],
        plannedRecipes: [Recipe] = [],
        existingListKeys: Set<String> = [],
        preferences: PreferenceSnapshot = .default,
        limit: Int = 12
    ) -> [ShoppingSuggestion] {

        let index = InventoryIndex(items: inventory, useSoonWindowDays: preferences.useSoonWindowDays)
        let avoided = preferences.avoidedIngredientKeys
        var results: [ShoppingSuggestion] = []
        var claimed = existingListKeys

        func isEligible(_ name: String) -> Bool {
            let key = IngredientNormaliser.key(for: name)
            guard !key.isEmpty, !claimed.contains(key) else { return false }
            guard !avoided.contains(where: { IngredientNormaliser.matches(name, $0) }) else { return false }
            return !index.contains(name)
        }

        // 1. Needed — required by something the user has planned to cook.
        for recipe in plannedRecipes {
            for ingredient in recipe.ingredients where !ingredient.isOptional {
                guard isEligible(ingredient.name) else { continue }
                claimed.insert(IngredientNormaliser.key(for: ingredient.name))
                results.append(
                    ShoppingSuggestion(
                        name: ingredient.name,
                        category: CategoryGuesser.category(for: ingredient.name),
                        quantity: ingredient.quantity > 0 ? ingredient.quantity : 1,
                        unit: ingredient.unit,
                        priority: .needed,
                        reason: String(localized: "Needed for \(recipe.title)"),
                        sourceRecipeTitle: recipe.title
                    )
                )
            }
        }

        // 2. Useful — count how many near-miss recipes each missing ingredient blocks.
        var blockedBy: [String: (name: String, unit: MeasurementUnit, quantity: Double, count: Int)] = [:]
        for recipe in recipes {
            let required = recipe.ingredients.filter { !$0.isOptional }
            let missing = required.filter { !index.contains($0.name) }
            // Only near misses are informative. A recipe missing six things tells us nothing.
            guard (1...2).contains(missing.count) else { continue }
            for ingredient in missing {
                let key = IngredientNormaliser.key(for: ingredient.name)
                guard !key.isEmpty else { continue }
                var entry = blockedBy[key] ?? (ingredient.name, ingredient.unit, ingredient.quantity, 0)
                entry.count += 1
                blockedBy[key] = entry
            }
        }

        let useful = blockedBy
            .filter { isEligible($0.value.name) && $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }

        for (key, entry) in useful {
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            results.append(
                ShoppingSuggestion(
                    name: entry.name,
                    category: CategoryGuesser.category(for: entry.name),
                    quantity: entry.quantity > 0 ? entry.quantity : 1,
                    unit: entry.unit,
                    priority: .useful,
                    reason: entry.count == 1
                        ? String(localized: "Unlocks 1 more recipe from your pantry")
                        : String(localized: "Unlocks \(entry.count) more recipes from your pantry"),
                    recipesUnlocked: entry.count
                )
            )
        }

        // 3. Optional — staples the user is nearly out of.
        for item in inventory where item.isRunningLow && item.quantity > 0 {
            let key = item.matchKey
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            results.append(
                ShoppingSuggestion(
                    name: item.name,
                    category: item.category,
                    quantity: item.unit.isCountable ? max(1, item.quantity) : item.unit.stepIncrement * 4,
                    unit: item.unit,
                    priority: .optional,
                    reason: String(localized: "Running low — \(item.quantityDescription) left")
                )
            )
        }

        return Array(
            results
                .sorted { lhs, rhs in
                    if lhs.priority.sortIndex != rhs.priority.sortIndex {
                        return lhs.priority.sortIndex < rhs.priority.sortIndex
                    }
                    return lhs.recipesUnlocked > rhs.recipesUnlocked
                }
                .prefix(limit)
        )
    }

    /// Missing ingredients for one recipe, ready to add to the list in a single action.
    static func suggestions(forMissingIn match: RecipeMatch) -> [ShoppingSuggestion] {
        match.missingIngredients.map { ingredient in
            ShoppingSuggestion(
                name: ingredient.name,
                category: CategoryGuesser.category(for: ingredient.name),
                quantity: ingredient.quantity > 0 ? ingredient.quantity : 1,
                unit: ingredient.unit,
                priority: .needed,
                reason: String(localized: "Needed for \(match.recipe.title)"),
                sourceRecipeTitle: match.recipe.title
            )
        }
    }
}
