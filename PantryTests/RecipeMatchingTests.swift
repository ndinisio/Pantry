import Testing
import Foundation
@testable import Pantry

@Suite("Recipe matching")
struct RecipeMatchingTests {

    // MARK: - Fixtures

    private func item(_ name: String, quantity: Double = 1, unit: MeasurementUnit = .piece, expiresInDays: Int? = nil) -> PantryItem {
        PantryItem(
            name: name,
            quantity: quantity,
            unit: unit,
            expirationDate: expiresInDays.flatMap {
                Calendar.current.date(byAdding: .day, value: $0, to: Date.now)
            }
        )
    }

    private func recipe(
        _ title: String,
        ingredients: [String],
        optional: [String] = [],
        minutes: Int = 20,
        tags: [String] = [],
        equipment: [String] = [],
        difficulty: RecipeDifficulty = .easy
    ) -> Recipe {
        let recipe = Recipe(
            title: title,
            cookTimeMinutes: minutes,
            difficulty: difficulty,
            tags: tags,
            equipment: equipment,
            steps: ["Cook it."]
        )
        recipe.ingredients =
            ingredients.enumerated().map { RecipeIngredient(name: $1, sortOrder: $0) }
            + optional.enumerated().map { RecipeIngredient(name: $1, isOptional: true, sortOrder: 100 + $0) }
        return recipe
    }

    // MARK: - Tests

    @Test("A recipe whose ingredients are all owned is cookable now")
    func identifiesCookableRecipes() throws {
        let inventory = [item("Eggs"), item("Cheddar"), item("Butter"), item("Spinach")]
        let recipes = [recipe("Omelette", ingredients: ["Eggs", "Cheddar", "Butter"])]

        let match = try #require(RecipeMatcher.match(recipes: recipes, inventory: inventory).first)
        #expect(match.canCookNow)
        #expect(match.missingIngredients.isEmpty)
        #expect(match.coverage == 1)
        #expect(match.stars == 5)
    }

    @Test("Missing ingredients are reported, not hidden")
    func reportsMissingIngredients() throws {
        let inventory = [item("Eggs"), item("Cheddar")]
        let recipes = [recipe("Omelette", ingredients: ["Eggs", "Cheddar", "Butter"])]

        var query = RecipeQuery()
        query.appetite = .almostNoShopping

        let match = try #require(RecipeMatcher.match(recipes: recipes, inventory: inventory, query: query).first)
        #expect(!match.canCookNow)
        #expect(match.missingIngredients.map(\.name) == ["Butter"])
    }

    @Test("Optional ingredients never make a recipe uncookable")
    func ignoresOptionalIngredients() throws {
        let inventory = [item("Pasta"), item("Chopped tomatoes")]
        let recipes = [recipe("Pasta", ingredients: ["Pasta", "Chopped tomatoes"], optional: ["Parmesan"])]

        let match = try #require(RecipeMatcher.match(recipes: recipes, inventory: inventory).first)
        #expect(match.canCookNow)
        #expect(match.missingOptionalIngredients.map(\.name) == ["Parmesan"])
    }

    @Test("Shopping appetite caps how many missing ingredients are acceptable")
    func respectsShoppingAppetite() {
        let inventory = [item("Eggs")]
        let recipes = [recipe("Cake", ingredients: ["Eggs", "Flour", "Sugar", "Butter"])]

        var strict = RecipeQuery()
        strict.appetite = .useWhatIHave
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, query: strict).isEmpty)

        var relaxed = RecipeQuery()
        relaxed.appetite = .almostNoShopping
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, query: relaxed).isEmpty)

        var open = RecipeQuery()
        open.appetite = .happyToShop
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, query: open).count == 1)
    }

    @Test("Recipes using food near its date are ranked above equally cookable ones")
    func prioritisesExpiringIngredients() throws {
        let inventory = [
            item("Spinach", expiresInDays: 1),
            item("Eggs", expiresInDays: 30),
            item("Cheddar", expiresInDays: 30),
            item("Butter", expiresInDays: 30),
            item("Rice", expiresInDays: 300)
        ]
        let recipes = [
            recipe("Rice Bowl", ingredients: ["Rice", "Eggs"]),
            recipe("Spinach Omelette", ingredients: ["Spinach", "Eggs", "Butter"])
        ]

        let matches = RecipeMatcher.match(recipes: recipes, inventory: inventory)
        let first = try #require(matches.first)
        #expect(first.recipe.title == "Spinach Omelette")
        #expect(!first.expiringItemsUsed.isEmpty)
    }

    @Test("An allergy excludes a recipe however well it otherwise scores")
    func excludesAllergens() {
        let inventory = [item("Peanuts"), item("Rice"), item("Soy sauce")]
        let recipes = [recipe("Peanut Rice", ingredients: ["Peanuts", "Rice", "Soy sauce"])]

        var preferences = PreferenceSnapshot()
        preferences.allergies = ["Peanuts"]

        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, preferences: preferences).isEmpty)
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory).count == 1)
    }

    @Test("A time limit removes recipes that take longer")
    func respectsTimeLimit() {
        let inventory = [item("Eggs"), item("Butter")]
        let recipes = [
            recipe("Quick Eggs", ingredients: ["Eggs", "Butter"], minutes: 10),
            recipe("Slow Eggs", ingredients: ["Eggs", "Butter"], minutes: 90)
        ]

        var query = RecipeQuery()
        query.maxTotalMinutes = 15
        let matches = RecipeMatcher.match(recipes: recipes, inventory: inventory, query: query)
        #expect(matches.count == 1)
        #expect(matches.first?.recipe.title == "Quick Eggs")
    }

    @Test("Recipes needing equipment the kitchen doesn't have are left out")
    func respectsEquipment() {
        let inventory = [item("Chicken breast")]
        let recipes = [recipe("Air Fried Chicken", ingredients: ["Chicken breast"], equipment: ["airFryer"])]

        var withoutFryer = PreferenceSnapshot()
        withoutFryer.equipment = [.hob, .oven]
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, preferences: withoutFryer).isEmpty)

        var withFryer = PreferenceSnapshot()
        withFryer.equipment = [.hob, .airFryer]
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, preferences: withFryer).count == 1)
    }

    @Test("A vegetarian diet only surfaces recipes tagged for it")
    func respectsDietaryStyle() {
        let inventory = [item("Eggs"), item("Chicken breast"), item("Cheddar")]
        let recipes = [
            recipe("Omelette", ingredients: ["Eggs", "Cheddar"], tags: ["vegetarian"]),
            recipe("Roast Chicken", ingredients: ["Chicken breast"])
        ]

        var preferences = PreferenceSnapshot()
        preferences.dietaryStyle = .vegetarian

        let matches = RecipeMatcher.match(recipes: recipes, inventory: inventory, preferences: preferences)
        #expect(matches.count == 1)
        #expect(matches.first?.recipe.title == "Omelette")
    }

    @Test("Asking to use something up excludes recipes that don't")
    func honoursMustUse() {
        let inventory = [item("Spinach"), item("Eggs"), item("Rice")]
        let recipes = [
            recipe("Spinach Eggs", ingredients: ["Spinach", "Eggs"]),
            recipe("Egg Rice", ingredients: ["Eggs", "Rice"])
        ]

        var query = RecipeQuery()
        query.mustUseKeys = [IngredientNormaliser.key(for: "Spinach")]

        let matches = RecipeMatcher.match(recipes: recipes, inventory: inventory, query: query)
        #expect(matches.count == 1)
        #expect(matches.first?.recipe.title == "Spinach Eggs")
    }

    @Test("Items with nothing left do not count as owned")
    func ignoresEmptyItems() {
        let inventory = [item("Eggs", quantity: 0), item("Butter")]
        let recipes = [recipe("Omelette", ingredients: ["Eggs", "Butter"])]

        var query = RecipeQuery()
        query.appetite = .useWhatIHave
        #expect(RecipeMatcher.match(recipes: recipes, inventory: inventory, query: query).isEmpty)
    }

    @Test("A general pantry item satisfies a more specific ingredient")
    func matchesRelatedNames() throws {
        let inventory = [item("Chicken"), item("Rice")]
        let recipes = [recipe("Chicken Rice", ingredients: ["Chicken breast", "Rice"])]

        let match = try #require(RecipeMatcher.match(recipes: recipes, inventory: inventory).first)
        #expect(match.canCookNow)
    }

    @Test("The bundled recipe library loads and is well formed")
    func libraryLoads() {
        let seeds = RecipeLibrary.loadSeed(bundle: .main)
        #expect(!seeds.isEmpty, "SeedRecipes.json should be in the app bundle")
        for seed in seeds {
            #expect(!seed.title.isEmpty)
            #expect(!seed.steps.isEmpty)
            #expect(!seed.ingredients.isEmpty)
            #expect(seed.servings > 0)
        }
    }
}
