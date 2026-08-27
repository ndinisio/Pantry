import Testing
import Foundation
@testable import Pantry

@Suite("Nutrition")
struct NutritionTests {

    private let full = NutritionFacts(
        calories: 520, proteinGrams: 38, carbohydrateGrams: 62, sugarGrams: 8,
        fatGrams: 12, saturatedFatGrams: 3, fibreGrams: 4, saltGrams: 1.2,
        source: .estimate
    )

    @Test("Every nutrient reads back the figure it was given")
    func readsEveryNutrient() {
        #expect(full.value(for: .calories) == 520)
        #expect(full.value(for: .protein) == 38)
        #expect(full.value(for: .carbohydrate) == 62)
        #expect(full.value(for: .sugar) == 8)
        #expect(full.value(for: .fat) == 12)
        #expect(full.value(for: .saturatedFat) == 3)
        #expect(full.value(for: .fibre) == 4)
        #expect(full.value(for: .salt) == 1.2)
    }

    @Test("A nutrient with no figure stays absent rather than becoming zero")
    func missingIsNotZero() {
        let partial = NutritionFacts(calories: 200, proteinGrams: 10)
        #expect(partial.value(for: .salt) == nil)
        #expect(partial.displayValue(for: .salt) == nil)
        #expect(partial.value(for: .calories) == 200)
    }

    @Test("Calories carry no unit; everything else is in grams")
    func formatsUnits() {
        #expect(full.displayValue(for: .calories) == "520")
        #expect(full.displayValue(for: .protein) == "38 g")
        #expect(full.displayValue(for: .salt) == "1.2 g")
    }

    @Test("Spoken values use words, not symbols")
    func formatsAccessibleValues() {
        #expect(full.accessibleValue(for: .protein)?.contains("grams") == true)
        #expect(full.accessibleValue(for: .calories)?.contains("calories") == true)
    }

    @Test("Emptiness means no figures at all, not a missing one")
    func detectsEmptiness() {
        #expect(NutritionFacts().isEmpty)
        #expect(!NutritionFacts(calories: 1).isEmpty)
        #expect(!full.isEmpty)
        #expect(full.hasAnyValue(among: [.salt]))
        #expect(!NutritionFacts(calories: 1).hasAnyValue(among: [.salt, .sugar]))
    }

    @Test("Selected nutrients come back in label order, whatever order they were stored")
    func preservesLabelOrder() {
        let selection = Nutrient.from(rawValues: ["salt", "calories", "fat"])
        #expect(selection == [.calories, .fat, .salt])
    }

    @Test("Unknown stored values are ignored rather than failing")
    func ignoresUnknownNutrients() {
        #expect(Nutrient.from(rawValues: ["calories", "vitaminQ"]) == [.calories])
        #expect(Nutrient.from(rawValues: []).isEmpty)
    }

    @Test("The standard set is the front-of-pack figures plus fibre")
    func standardSelection() {
        #expect(Nutrient.defaultSelection == [.calories, .protein, .carbohydrate, .fat, .fibre])
    }

    @Test("Older stored nutrition decodes without the nutrients added later")
    func decodesOlderData() throws {
        let legacy = #"{"calories":520,"proteinGrams":38,"source":"estimate"}"#
        let decoded = try JSONDecoder().decode(NutritionFacts.self, from: Data(legacy.utf8))
        #expect(decoded.calories == 520)
        #expect(decoded.saltGrams == nil)
        #expect(decoded.isEstimated)
    }

    @Test("Product figures are not labelled as estimates")
    func distinguishesProductFromEstimate() {
        #expect(NutritionFacts(calories: 100, source: .product).isEstimated == false)
        #expect(NutritionFacts(calories: 100, source: .estimate).isEstimated)
    }

    @Test("Preferences carry the tracked set through to the snapshot")
    func snapshotCarriesSelection() {
        let preferences = UserPreferences()
        preferences.selectedNutrients = [.calories, .salt]
        #expect(PreferenceSnapshot(preferences).trackedNutrients == [.calories, .salt])
        #expect(PreferenceSnapshot().trackedNutrients == Nutrient.defaultSelection)
    }

    @Test("Every library recipe provides the standard set")
    func libraryRecipesCarryNutrition() {
        let seeds = RecipeLibrary.loadSeed(bundle: .main)
        #expect(!seeds.isEmpty)
        for seed in seeds {
            let recipe = RecipeLibrary.makeRecipe(from: seed)
            let nutrition = recipe.nutrition
            #expect(nutrition != nil, "\(seed.title) has no nutrition")
            #expect(nutrition?.hasAnyValue(among: Nutrient.defaultSelection) == true, "\(seed.title)")
            #expect(nutrition?.isEstimated == true, "\(seed.title) should be marked an estimate")
        }
    }
}
