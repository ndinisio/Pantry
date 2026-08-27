import Testing
import Foundation
import SwiftData
@testable import Pantry

@Suite("Natural language input")
struct NaturalLanguageParsingTests {

    @Test("A sentence becomes several items")
    func parsesASentence() throws {
        let items = NaturalLanguageItemParser.parse("I bought 2 litres of milk, a pack of chicken breasts and six eggs.")
        #expect(items.count == 3)

        let milk = try #require(items.first { $0.name.localizedCaseInsensitiveContains("milk") })
        #expect(milk.quantity == 2)
        #expect(milk.unit == .litre)

        let chicken = try #require(items.first { $0.name.localizedCaseInsensitiveContains("chicken") })
        #expect(chicken.quantity == 1)
        #expect(chicken.unit == .pack)

        let eggs = try #require(items.first { $0.name.localizedCaseInsensitiveContains("egg") })
        #expect(eggs.quantity == 6)
    }

    @Test("A number attached to its unit is understood")
    func parsesCompactQuantities() throws {
        let item = try #require(NaturalLanguageItemParser.parseFragment("500g chicken"))
        #expect(item.quantity == 500)
        #expect(item.unit == .gram)
        #expect(item.name == "Chicken")
    }

    @Test("Number words are understood, including a second one that multiplies")
    func parsesNumberWords() throws {
        #expect(try #require(NaturalLanguageItemParser.parseFragment("six eggs")).quantity == 6)
        #expect(try #require(NaturalLanguageItemParser.parseFragment("a dozen eggs")).quantity == 12)
        #expect(try #require(NaturalLanguageItemParser.parseFragment("two dozen eggs")).quantity == 24)
    }

    @Test("Sentence punctuation is not part of the name")
    func stripsTrailingPunctuation() throws {
        let item = try #require(NaturalLanguageItemParser.parseFragment("six eggs."))
        #expect(item.name == "Eggs")
    }

    @Test("A bare name defaults to one, with a guessed unit and category")
    func defaultsBareNames() throws {
        let item = try #require(NaturalLanguageItemParser.parseFragment("rice"))
        #expect(item.quantity == 1)
        #expect(item.name == "Rice")
        #expect(item.category == .grains)
    }

    @Test("Names are title-cased for display")
    func capitalisesNames() throws {
        let item = try #require(NaturalLanguageItemParser.parseFragment("greek yogurt"))
        #expect(item.name == "Greek Yogurt")
    }

    @Test("A list, one per line, parses line by line")
    func parsesLines() {
        let items = NaturalLanguageItemParser.parseLines("Milk\nEggs\nChicken breast\nRice\nTomatoes")
        #expect(items.count == 5)
        #expect(items.map(\.name).contains("Chicken Breast"))
    }

    @Test("Empty and whitespace-only input produces nothing")
    func handlesEmptyInput() {
        #expect(NaturalLanguageItemParser.parse("").isEmpty)
        #expect(NaturalLanguageItemParser.parse("   \n  ").isEmpty)
        #expect(NaturalLanguageItemParser.parseFragment("   ") == nil)
    }

    @Test("A quantity with no food is not an item")
    func ignoresQuantityWithoutAName() {
        #expect(NaturalLanguageItemParser.parseFragment("500g") == nil)
    }
}

@Suite("Shopping suggestions")
struct ShoppingSuggestionTests {

    private func item(_ name: String, quantity: Double = 5, unit: MeasurementUnit = .piece) -> PantryItem {
        PantryItem(name: name, quantity: quantity, unit: unit)
    }

    private func recipe(_ title: String, ingredients: [String]) -> Recipe {
        let recipe = Recipe(title: title, steps: ["Cook."])
        recipe.ingredients = ingredients.enumerated().map { RecipeIngredient(name: $1, sortOrder: $0) }
        return recipe
    }

    @Test("An ingredient blocking several near-miss recipes is suggested, with the count")
    func suggestsHighLeverageIngredients() throws {
        let inventory = [item("Rice"), item("Pasta"), item("Chopped tomatoes"), item("Garlic")]
        let recipes = [
            recipe("Chicken Rice", ingredients: ["Rice", "Chicken breast"]),
            recipe("Chicken Pasta", ingredients: ["Pasta", "Chicken breast"]),
            recipe("Chicken Tomato", ingredients: ["Chopped tomatoes", "Chicken breast"])
        ]

        let suggestions = ShoppingSuggestionEngine.suggestions(inventory: inventory, recipes: recipes)
        let chicken = try #require(suggestions.first { $0.name.localizedCaseInsensitiveContains("chicken") })
        #expect(chicken.priority == .useful)
        #expect(chicken.recipesUnlocked == 3)
        #expect(chicken.reason.contains("3"))
    }

    @Test("Ingredients for planned meals are needed, and name the meal")
    func marksPlannedIngredientsAsNeeded() throws {
        let inventory = [item("Rice")]
        let planned = recipe("Chicken Fried Rice", ingredients: ["Rice", "Spring onions"])

        let suggestions = ShoppingSuggestionEngine.suggestions(
            inventory: inventory,
            recipes: [planned],
            plannedRecipes: [planned]
        )
        let onions = try #require(suggestions.first { $0.name.localizedCaseInsensitiveContains("spring onion") })
        #expect(onions.priority == .needed)
        #expect(onions.reason.contains("Chicken Fried Rice"))
    }

    @Test("Nothing already in the pantry is suggested")
    func neverSuggestsWhatIsOwned() {
        let inventory = [item("Rice"), item("Chicken breast")]
        let recipes = [recipe("Chicken Rice", ingredients: ["Rice", "Chicken breast"])]

        let suggestions = ShoppingSuggestionEngine.suggestions(inventory: inventory, recipes: recipes)
        #expect(!suggestions.contains { $0.name.localizedCaseInsensitiveContains("rice") })
    }

    @Test("Nothing already on the list is suggested again")
    func neverDuplicatesTheList() {
        let inventory = [item("Rice"), item("Pasta")]
        let recipes = [
            recipe("A", ingredients: ["Rice", "Chicken breast"]),
            recipe("B", ingredients: ["Pasta", "Chicken breast"])
        ]

        let suggestions = ShoppingSuggestionEngine.suggestions(
            inventory: inventory,
            recipes: recipes,
            existingListKeys: [IngredientNormaliser.key(for: "Chicken breast")]
        )
        #expect(!suggestions.contains { $0.name.localizedCaseInsensitiveContains("chicken") })
    }

    @Test("Allergens are never suggested")
    func neverSuggestsAllergens() {
        let inventory = [item("Rice"), item("Pasta")]
        let recipes = [
            recipe("A", ingredients: ["Rice", "Peanuts"]),
            recipe("B", ingredients: ["Pasta", "Peanuts"])
        ]
        var preferences = PreferenceSnapshot()
        preferences.allergies = ["Peanuts"]

        let suggestions = ShoppingSuggestionEngine.suggestions(
            inventory: inventory,
            recipes: recipes,
            preferences: preferences
        )
        #expect(!suggestions.contains { $0.name.localizedCaseInsensitiveContains("peanut") })
    }

    @Test("Something nearly gone is offered as optional")
    func flagsItemsRunningLow() throws {
        let inventory = [item("Olive oil", quantity: 1, unit: .piece)]
        let suggestions = ShoppingSuggestionEngine.suggestions(inventory: inventory, recipes: [])
        let oil = try #require(suggestions.first { $0.name.localizedCaseInsensitiveContains("olive oil") })
        #expect(oil.priority == .optional)
    }

    @Test("Needed comes before useful, which comes before optional")
    func ordersByPriority() {
        let inventory = [item("Rice"), item("Pasta"), item("Salt", quantity: 1)]
        let planned = recipe("Planned", ingredients: ["Rice", "Fish"])
        let recipes = [
            planned,
            recipe("A", ingredients: ["Rice", "Chicken breast"]),
            recipe("B", ingredients: ["Pasta", "Chicken breast"])
        ]

        let suggestions = ShoppingSuggestionEngine.suggestions(
            inventory: inventory,
            recipes: recipes,
            plannedRecipes: [planned]
        )
        let indices = suggestions.map(\.priority.sortIndex)
        #expect(indices == indices.sorted())
    }

    @Test("Missing ingredients for one recipe convert to needed items")
    func convertsRecipeMisses() throws {
        let inventory = [item("Rice")]
        let target = recipe("Chicken Rice", ingredients: ["Rice", "Chicken breast"])

        var query = RecipeQuery()
        query.appetite = .almostNoShopping
        let match = try #require(RecipeMatcher.match(recipes: [target], inventory: inventory, query: query).first)

        let suggestions = ShoppingSuggestionEngine.suggestions(forMissingIn: match)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.priority == .needed)
        #expect(suggestions.first?.sourceRecipeTitle == "Chicken Rice")
    }
}

@MainActor
@Suite("Inventory service")
struct InventoryServiceTests {

    private func makeService() -> (InventoryService, ModelContext) {
        let container = PantryModelContainer.makeContainer(inMemory: true)
        return (InventoryService(context: container.mainContext), container.mainContext)
    }

    @Test("Adding the same thing twice combines the quantities")
    func mergesDuplicates() {
        let (service, _) = makeService()
        service.add([PantryItem(name: "Milk", quantity: 1, unit: .litre)])
        service.add([PantryItem(name: "milk", quantity: 2, unit: .litre)])

        let items = service.allItems()
        #expect(items.count == 1)
        #expect(items.first?.quantity == 3)
    }

    @Test("Different units stay as separate entries rather than being guessed at")
    func keepsIncompatibleUnitsApart() {
        let (service, _) = makeService()
        service.add([PantryItem(name: "Rice", quantity: 1, unit: .kilogram)])
        service.add([PantryItem(name: "Rice", quantity: 2, unit: .pack)])
        #expect(service.allItems().count == 2)
    }

    @Test("Quantity never goes below zero")
    func clampsQuantityAtZero() {
        let (service, _) = makeService()
        let item = service.add(PantryItem(name: "Eggs", quantity: 2, unit: .piece))
        service.adjustQuantity(of: item, by: -10)
        #expect(item.quantity == 0)
    }

    @Test("Cooking subtracts what was used, scaled to the servings cooked")
    func consumesIngredients() throws {
        let (service, context) = makeService()
        let rice = service.add(PantryItem(name: "Rice", quantity: 1000, unit: .gram))
        let eggs = service.add(PantryItem(name: "Eggs", quantity: 6, unit: .piece))

        let recipe = Recipe(title: "Egg Rice", servings: 2, steps: ["Cook."])
        recipe.ingredients = [
            RecipeIngredient(name: "Rice", quantity: 200, unit: .gram, sortOrder: 0),
            RecipeIngredient(name: "Eggs", quantity: 2, unit: .piece, sortOrder: 1)
        ]
        context.insert(recipe)

        service.markCooked(recipe, servings: 4, consumeInventory: true)

        #expect(rice.quantity == 600)
        #expect(eggs.quantity == 2)
        #expect(recipe.timesCooked == 1)
        #expect(recipe.lastCookedDate != nil)
    }

    @Test("Cooking converts units where that is meaningful")
    func convertsUnitsWhenConsuming() {
        let (service, context) = makeService()
        let rice = service.add(PantryItem(name: "Rice", quantity: 2, unit: .kilogram))

        let recipe = Recipe(title: "Rice", servings: 1, steps: ["Cook."])
        recipe.ingredients = [RecipeIngredient(name: "Rice", quantity: 500, unit: .gram, sortOrder: 0)]
        context.insert(recipe)

        service.markCooked(recipe, servings: 1, consumeInventory: true)
        #expect(rice.quantity == 1.5)
    }

    @Test("Ingredients that can't be reconciled are left alone rather than guessed at")
    func leavesAmbiguousUnitsAlone() {
        let (service, context) = makeService()
        let rice = service.add(PantryItem(name: "Rice", quantity: 2, unit: .pack))

        let recipe = Recipe(title: "Rice", servings: 1, steps: ["Cook."])
        recipe.ingredients = [RecipeIngredient(name: "Rice", quantity: 200, unit: .gram, sortOrder: 0)]
        context.insert(recipe)

        service.markCooked(recipe, servings: 1, consumeInventory: true)
        #expect(rice.quantity == 2)
    }

    @Test("Cooking without updating the pantry leaves quantities untouched")
    func canCookWithoutConsuming() {
        let (service, context) = makeService()
        let rice = service.add(PantryItem(name: "Rice", quantity: 1000, unit: .gram))

        let recipe = Recipe(title: "Rice", servings: 1, steps: ["Cook."])
        recipe.ingredients = [RecipeIngredient(name: "Rice", quantity: 200, unit: .gram, sortOrder: 0)]
        context.insert(recipe)

        service.markCooked(recipe, servings: 1, consumeInventory: false)
        #expect(rice.quantity == 1000)
        #expect(recipe.timesCooked == 1)
    }

    @Test("Only items with a date, and only those near it, need attention")
    func findsItemsNeedingAttention() {
        let (service, _) = makeService()
        service.add(PantryItem(name: "Spinach", expirationDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)))
        service.add(PantryItem(name: "Rice", expirationDate: Calendar.current.date(byAdding: .day, value: 300, to: .now)))
        service.add(PantryItem(name: "Salt"))

        let needing = service.itemsNeedingAttention()
        #expect(needing.count == 1)
        #expect(needing.first?.name == "Spinach")
    }

    @Test("The summary counts what the Home screen and the widget display")
    func summarisesInventory() {
        let (service, _) = makeService()
        service.add(PantryItem(name: "Spinach", category: .produce,
                               expirationDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                               location: .fridge))
        service.add(PantryItem(name: "Rice", category: .grains, location: .cupboard))
        service.add(PantryItem(name: "Old Yoghurt", category: .dairy,
                               expirationDate: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                               location: .fridge))

        let summary = service.counts()
        #expect(summary.totalItems == 3)
        #expect(summary.expiringSoon == 1)
        #expect(summary.pastDate == 1)
        #expect(summary.byLocation[.fridge] == 2)
        #expect(summary.byCategory[.grains] == 1)
    }

    @Test("Sample content can be added and then removed without touching user items")
    func sampleDataIsSeparable() {
        let container = PantryModelContainer.makeContainer(inMemory: true)
        let context = container.mainContext
        let service = InventoryService(context: context)

        service.add(PantryItem(name: "My Own Thing"))
        SampleData.populate(context: context)
        #expect(SampleData.isPresent(in: context))
        #expect(service.allItems().count > 1)

        SampleData.remove(context: context)
        let remaining = service.allItems()
        #expect(!SampleData.isPresent(in: context))
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "My Own Thing")
    }

    @Test("The recipe library installs once and is not duplicated on relaunch")
    func recipeLibraryIsIdempotent() {
        let container = PantryModelContainer.makeContainer(inMemory: true)
        let context = container.mainContext

        RecipeLibrary.installIfNeeded(context: context)
        let first = (try? context.fetch(FetchDescriptor<Recipe>()))?.count ?? 0
        RecipeLibrary.installIfNeeded(context: context)
        let second = (try? context.fetch(FetchDescriptor<Recipe>()))?.count ?? 0

        #expect(first > 0)
        #expect(first == second)
    }
}
