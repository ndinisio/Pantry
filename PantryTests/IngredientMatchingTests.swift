import Testing
@testable import Pantry

@Suite("Ingredient normalisation and matching")
struct IngredientMatchingTests {

    @Test("Case, spacing and diacritics collapse to the same key")
    func normalisesSurfaceDifferences() {
        #expect(IngredientNormaliser.key(for: "Tomatoes") == IngredientNormaliser.key(for: "tomato"))
        #expect(IngredientNormaliser.key(for: "  Fresh Tomato ") == IngredientNormaliser.key(for: "tomato"))
        #expect(IngredientNormaliser.key(for: "Crème Fraîche") == IngredientNormaliser.key(for: "creme fraiche"))
    }

    @Test("Descriptive words are dropped but the food is kept")
    func dropsNoiseWords() {
        #expect(IngredientNormaliser.key(for: "finely chopped garlic") == "garlic")
        #expect(IngredientNormaliser.key(for: "large free range eggs") == "egg")
    }

    @Test("Irregular plurals singularise correctly")
    func handlesIrregularPlurals() {
        #expect(IngredientNormaliser.key(for: "potatoes") == "potato")
        #expect(IngredientNormaliser.key(for: "cherries") == "cherry")
        #expect(IngredientNormaliser.key(for: "bay leaves") == "bay leaf")
    }

    @Test("Words ending in double-s are not truncated")
    func doesNotOverSingularise() {
        #expect(IngredientNormaliser.key(for: "watercress") == "watercress")
        #expect(IngredientNormaliser.key(for: "couscous") == "couscous")
    }

    @Test("A name made only of descriptors still produces a key")
    func neverProducesAnEmptyKey() {
        // Every token is noise, so the fallback keeps the cleaned text rather than
        // collapsing two different items onto the same empty key.
        #expect(IngredientNormaliser.key(for: "fresh chopped") == "fresh chopped")
    }

    @Test("A general ingredient matches a specific one, in both directions")
    func matchesPartialNames() {
        #expect(IngredientNormaliser.matches("chicken", "chicken breast"))
        #expect(IngredientNormaliser.matches("chicken breast", "chicken"))
    }

    @Test("Unrelated foods do not match")
    func doesNotMatchUnrelatedFoods() {
        #expect(!IngredientNormaliser.matches("chicken", "chickpea"))
        #expect(!IngredientNormaliser.matches("milk", "flour"))
    }

    @Test("Matching is on whole words, so a food is never confused with a longer one")
    func matchesOnWordBoundariesOnly() {
        #expect(!IngredientNormaliser.matches("egg", "eggplant"))
        #expect(!IngredientNormaliser.matches("corn", "cornflour"))
        #expect(!IngredientNormaliser.matches("lime", "limeade"))
        // The legitimate case still works.
        #expect(IngredientNormaliser.matches("rice", "basmati rice"))
        #expect(IngredientNormaliser.matches("soy sauce", "dark soy sauce"))
    }
}

@Suite("Category and unit guessing")
struct CategoryGuesserTests {

    @Test("Common foods land in the right category", arguments: [
        ("Chicken breast", FoodCategory.meatAndFish),
        ("Greek yogurt", FoodCategory.dairy),
        ("Spinach", FoodCategory.produce),
        ("Basmati rice", FoodCategory.grains),
        ("Soy sauce", FoodCategory.saucesAndCondiments),
        ("Chopped tomatoes", FoodCategory.cannedAndJarred),
        ("Paprika", FoodCategory.spices)
    ])
    func categorisesCommonFoods(name: String, expected: FoodCategory) {
        #expect(CategoryGuesser.category(for: name) == expected)
    }

    @Test("Frozen wins over the underlying food")
    func frozenTakesPrecedence() {
        #expect(CategoryGuesser.category(for: "Frozen peas") == .frozen)
        #expect(CategoryGuesser.category(for: "Frozen chicken") == .frozen)
    }

    @Test("The most specific keyword wins")
    func prefersLongerKeywords() {
        #expect(CategoryGuesser.category(for: "Coconut milk") == .cannedAndJarred)
    }

    @Test("Unknown foods fall back to Other rather than guessing")
    func fallsBackToOther() {
        #expect(CategoryGuesser.category(for: "Zorblax") == .other)
    }

    @Test("Liquids default to a volume unit")
    func guessesUnits() {
        #expect(CategoryGuesser.unit(for: "Milk") == .millilitre)
        #expect(CategoryGuesser.unit(for: "Olive oil") == .millilitre)
        #expect(CategoryGuesser.unit(for: "Chicken breast") == .gram)
        #expect(CategoryGuesser.unit(for: "Apples") == .piece)
    }

    @Test("A word that merely contains a liquid's name is not treated as a liquid")
    func doesNotMistakeSubstringsForLiquids() {
        // "boiled" contains "oil".
        #expect(CategoryGuesser.unit(for: "Boiled eggs") != .millilitre)
    }
}
