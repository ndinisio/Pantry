import Foundation

/// How much shopping the user is willing to do for a given suggestion.
enum ShoppingAppetite: String, CaseIterable, Identifiable, Sendable {
    /// Only recipes that need nothing extra.
    case useWhatIHave
    /// Up to two missing ingredients.
    case almostNoShopping
    /// Anything, ranked by how much is already owned.
    case happyToShop

    var id: String { rawValue }

    var name: String {
        switch self {
        case .useWhatIHave: return String(localized: "Use what I have")
        case .almostNoShopping: return String(localized: "Almost no shopping")
        case .happyToShop: return String(localized: "Happy to shop")
        }
    }

    var maximumMissingIngredients: Int {
        switch self {
        case .useWhatIHave: return 0
        case .almostNoShopping: return 2
        case .happyToShop: return Int.max
        }
    }
}

/// The constraints behind "What can I make?".
struct RecipeQuery: Equatable, Sendable {
    var maxTotalMinutes: Int?
    var mealType: MealType?
    var maxDifficulty: RecipeDifficulty?
    var appetite: ShoppingAppetite = .almostNoShopping
    /// Normalised keys of ingredients the user specifically wants to use up.
    var mustUseKeys: Set<String> = []
    /// Normalised keys of ingredients to keep out of suggestions.
    var avoidKeys: Set<String> = []
    var requiredTags: Set<String> = []

    static let anything = RecipeQuery()
}

/// A recipe scored against what the user actually owns.
struct RecipeMatch: Identifiable {
    let recipeID: UUID
    let recipe: Recipe
    /// Required ingredients the user has.
    let ownedIngredients: [RecipeIngredient]
    /// Required ingredients the user does not have.
    let missingIngredients: [RecipeIngredient]
    /// Optional ingredients the user does not have. Never counted against a recipe.
    let missingOptionalIngredients: [RecipeIngredient]
    /// Pantry items this recipe would use that are close to their date.
    let expiringItemsUsed: [PantryItem]
    let score: Double

    var id: UUID { recipeID }

    /// Share of required ingredients already in the pantry, 0...1.
    var coverage: Double {
        let total = ownedIngredients.count + missingIngredients.count
        guard total > 0 else { return 1 }
        return Double(ownedIngredients.count) / Double(total)
    }

    var canCookNow: Bool { missingIngredients.isEmpty }

    /// Headline shown above a recipe row.
    var availabilityDescription: String {
        if canCookNow { return String(localized: "Ready with your pantry") }
        if missingIngredients.count == 1 {
            return String(localized: "Missing 1 ingredient")
        }
        return String(localized: "Missing \(missingIngredients.count) ingredients")
    }

    /// 1...5, used for the compact rating shown on a recipe card.
    var stars: Int {
        max(1, min(5, Int((coverage * 5).rounded())))
    }
}

/// Matches recipes against inventory. Pure, synchronous and testable — no storage,
/// no network, no model context.
enum RecipeMatcher {

    /// Ranks `recipes` against `inventory`.
    ///
    /// - Parameters:
    ///   - useSoonWindowDays: how many days count as "expiring soon" for the bonus.
    ///   - limit: maximum matches returned, after filtering.
    static func match(
        recipes: [Recipe],
        inventory: [PantryItem],
        query: RecipeQuery = .anything,
        preferences: PreferenceSnapshot = .default,
        useSoonWindowDays: Int = 3,
        now: Date = .now,
        limit: Int = 50
    ) -> [RecipeMatch] {

        let stock = InventoryIndex(items: inventory, useSoonWindowDays: useSoonWindowDays, now: now)
        let avoided = query.avoidKeys.union(preferences.avoidedIngredientKeys)

        var matches: [RecipeMatch] = []
        matches.reserveCapacity(recipes.count)

        for recipe in recipes {
            guard passesHardFilters(recipe, query: query, preferences: preferences) else { continue }

            let required = recipe.ingredients.filter { !$0.isOptional }
            let optional = recipe.ingredients.filter(\.isOptional)

            // A recipe containing something the user avoids is never a suggestion,
            // however well it otherwise scores.
            let containsAvoided = recipe.ingredients.contains { ingredient in
                avoided.contains { IngredientNormaliser.matches(ingredient.name, $0) }
            }
            if containsAvoided { continue }

            var owned: [RecipeIngredient] = []
            var missing: [RecipeIngredient] = []
            for ingredient in required {
                if stock.contains(ingredient.name) { owned.append(ingredient) } else { missing.append(ingredient) }
            }
            let missingOptional = optional.filter { !stock.contains($0.name) }

            guard missing.count <= query.appetite.maximumMissingIngredients else { continue }

            // "Use these up" is a hard requirement when the user asked for it.
            if !query.mustUseKeys.isEmpty {
                let usesAll = query.mustUseKeys.allSatisfy { key in
                    recipe.ingredients.contains { IngredientNormaliser.matches($0.name, key) }
                }
                guard usesAll else { continue }
            }

            let expiring = stock.expiringItems(matching: recipe.ingredients.map(\.name))

            let match = RecipeMatch(
                recipeID: recipe.id,
                recipe: recipe,
                ownedIngredients: owned,
                missingIngredients: missing,
                missingOptionalIngredients: missingOptional,
                expiringItemsUsed: expiring,
                score: score(
                    recipe: recipe,
                    ownedCount: owned.count,
                    missingCount: missing.count,
                    expiringUsed: expiring.count,
                    preferences: preferences
                )
            )
            matches.append(match)
        }

        return Array(
            matches
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.recipe.totalTimeMinutes < rhs.recipe.totalTimeMinutes
                }
                .prefix(limit)
        )
    }

    /// Recipes that would use up a specific item, best first.
    static func recipes(using item: PantryItem, from recipes: [Recipe], inventory: [PantryItem], limit: Int = 5) -> [RecipeMatch] {
        var query = RecipeQuery()
        query.appetite = .almostNoShopping
        query.mustUseKeys = [item.matchKey]
        return match(recipes: recipes, inventory: inventory, query: query, limit: limit)
    }

    // MARK: - Private

    private static func passesHardFilters(
        _ recipe: Recipe,
        query: RecipeQuery,
        preferences: PreferenceSnapshot
    ) -> Bool {
        if let maxMinutes = query.maxTotalMinutes, recipe.totalTimeMinutes > maxMinutes { return false }
        if let maxDifficulty = query.maxDifficulty,
           difficultyRank(recipe.difficulty) > difficultyRank(maxDifficulty) { return false }

        let recipeTags = Set(recipe.tags)
        if !query.requiredTags.isEmpty, !query.requiredTags.isSubset(of: recipeTags) { return false }

        let dietTags = preferences.dietaryStyle.requiredRecipeTags
        if !dietTags.isEmpty, dietTags.isDisjoint(with: recipeTags) { return false }

        // Respect the kitchen the user actually has.
        if !preferences.equipment.isEmpty, !recipe.equipment.isEmpty {
            let availableEquipment = Set(preferences.equipment.map(\.rawValue))
            if Set(recipe.equipment).isDisjoint(with: availableEquipment) { return false }
        }
        return true
    }

    private static func difficultyRank(_ difficulty: RecipeDifficulty) -> Int {
        switch difficulty {
        case .easy: return 0
        case .medium: return 1
        case .involved: return 2
        }
    }

    /// Weights are deliberately blunt and readable: coverage dominates, using up food
    /// that is about to go is the main tiebreaker, and preferences nudge from there.
    private static func score(
        recipe: Recipe,
        ownedCount: Int,
        missingCount: Int,
        expiringUsed: Int,
        preferences: PreferenceSnapshot
    ) -> Double {
        let total = max(1, ownedCount + missingCount)
        let coverage = Double(ownedCount) / Double(total)

        var score = coverage * 100
        score -= Double(missingCount) * 12
        score += Double(min(expiringUsed, 3)) * 15

        if recipe.totalTimeMinutes <= preferences.maxCookingTimeMinutes { score += 8 }
        if recipe.totalTimeMinutes <= 20 { score += 4 }

        let recipeTags = Set(recipe.tags)
        if !preferences.dietaryStyle.requiredRecipeTags.isDisjoint(with: recipeTags) { score += 6 }
        if let cuisine = recipe.cuisine, preferences.favouriteCuisines.contains(where: { $0.caseInsensitiveCompare(cuisine) == .orderedSame }) {
            score += 6
        }
        if difficultyRank(recipe.difficulty) <= difficultyRank(preferences.skillLevel) { score += 4 }

        // Gently favour variety over what was cooked most recently.
        if let lastCooked = recipe.lastCookedDate,
           let days = ExpirationCalculator.daysUntil(lastCooked).map({ abs($0) }),
           days < 7 {
            score -= Double(7 - days) * 2
        }
        return score
    }
}

/// A read-only view over inventory, built once per match run so lookups stay cheap.
struct InventoryIndex {
    private let keys: Set<String>
    private let itemsByKey: [String: PantryItem]
    private let expiringKeys: Set<String>

    init(items: [PantryItem], useSoonWindowDays: Int, now: Date = .now) {
        var keys = Set<String>()
        var itemsByKey: [String: PantryItem] = [:]
        var expiring = Set<String>()

        for item in items where item.quantity > 0 {
            let key = item.matchKey
            keys.insert(key)
            itemsByKey[key] = item
            let state = ExpirationCalculator.freshness(
                for: item.expirationDate,
                useSoonWindowDays: useSoonWindowDays,
                now: now
            )
            if state.isNoteworthy { expiring.insert(key) }
        }

        self.keys = keys
        self.itemsByKey = itemsByKey
        self.expiringKeys = expiring
    }

    func contains(_ name: String) -> Bool {
        let key = IngredientNormaliser.key(for: name)
        if keys.contains(key) { return true }
        // "chicken" in a recipe is satisfied by "chicken breast" and vice versa —
        // but only on whole words, so "egg" never matches "eggplant".
        return keys.contains { IngredientNormaliser.contains($0, key) || IngredientNormaliser.contains(key, $0) }
    }

    func item(for name: String) -> PantryItem? {
        let key = IngredientNormaliser.key(for: name)
        if let exact = itemsByKey[key] { return exact }
        return itemsByKey.first {
            IngredientNormaliser.contains($0.key, key) || IngredientNormaliser.contains(key, $0.key)
        }?.value
    }

    func expiringItems(matching names: [String]) -> [PantryItem] {
        var seen = Set<UUID>()
        var result: [PantryItem] = []
        for name in names {
            let key = IngredientNormaliser.key(for: name)
            for expiringKey in expiringKeys
            where IngredientNormaliser.contains(expiringKey, key) || IngredientNormaliser.contains(key, expiringKey) {
                if let item = itemsByKey[expiringKey], !seen.contains(item.id) {
                    seen.insert(item.id)
                    result.append(item)
                }
            }
        }
        return result
    }
}

/// A plain-value copy of the user's preferences, so matching and the AI context layer
/// never need to touch a `ModelContext`.
struct PreferenceSnapshot: Equatable, Sendable {
    var dietaryStyle: DietaryStyle = .noPreference
    var allergies: [String] = []
    var dislikedFoods: [String] = []
    var favouriteCuisines: [String] = []
    var defaultServings: Int = 2
    var skillLevel: RecipeDifficulty = .easy
    var maxCookingTimeMinutes: Int = 45
    var equipment: [CookingEquipment] = CookingEquipment.defaultSelection
    var budgetPreference: BudgetPreference = .balanced
    var useSoonWindowDays: Int = 3

    static let `default` = PreferenceSnapshot()

    var avoidedIngredientKeys: Set<String> {
        Set((allergies + dislikedFoods).map { IngredientNormaliser.key(for: $0) })
    }

    init() {}

    init(_ preferences: UserPreferences) {
        dietaryStyle = preferences.dietaryStyle
        allergies = preferences.allergies
        dislikedFoods = preferences.dislikedFoods
        favouriteCuisines = preferences.favouriteCuisines
        defaultServings = preferences.defaultServings
        skillLevel = preferences.skillLevel
        maxCookingTimeMinutes = preferences.maxCookingTimeMinutes
        equipment = preferences.selectedEquipment
        budgetPreference = preferences.budgetPreference
        useSoonWindowDays = preferences.useSoonWindowDays
    }
}
