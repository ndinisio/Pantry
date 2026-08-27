import Foundation
import SwiftData
import OSLog

/// The recipe collection that ships with the app.
///
/// This is what makes Pantry useful with no network and no AI: matching runs against
/// these recipes locally. AI adds to the collection, it isn't required to have one.
enum RecipeLibrary {

    private static let logger = Logger(subsystem: PantryLog.subsystem, category: "RecipeLibrary")
    private static let resourceName = "SeedRecipes"

    // MARK: - Decoding

    struct Seed: Decodable {
        var version: Int
        var recipes: [SeedRecipe]
    }

    struct SeedRecipe: Decodable {
        var title: String
        var summary: String
        var prepTimeMinutes: Int
        var cookTimeMinutes: Int
        var servings: Int
        var difficulty: String
        var cuisine: String?
        var tags: [String]
        var equipment: [String]
        var ingredients: [SeedIngredient]
        var steps: [String]
        var nutrition: SeedNutrition?
    }

    struct SeedIngredient: Decodable {
        var name: String
        var quantity: Double?
        var unit: String?
        var preparation: String?
        var isOptional: Bool?
        var substitutions: [String]?
    }

    struct SeedNutrition: Decodable {
        var calories: Double?
        var proteinGrams: Double?
        var carbohydrateGrams: Double?
        var fatGrams: Double?
        var fibreGrams: Double?
    }

    // MARK: - Loading

    static func loadSeed(bundle: Bundle = .main) -> [SeedRecipe] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            logger.error("SeedRecipes.json is missing from the bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Seed.self, from: data).recipes
        } catch {
            logger.error("Could not decode the recipe library: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Inserts the library on first launch. Idempotent: existing library recipes are
    /// left alone so the user's saved state and cook counts survive relaunches.
    static func installIfNeeded(context: ModelContext, bundle: Bundle = .main) {
        let descriptor = FetchDescriptor<Recipe>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingTitles = Set(existing.map { $0.title.lowercased() })

        var inserted = 0
        for seed in loadSeed(bundle: bundle) where !existingTitles.contains(seed.title.lowercased()) {
            context.insert(makeRecipe(from: seed))
            inserted += 1
        }
        if inserted > 0 {
            try? context.save()
            logger.info("Installed \(inserted, privacy: .public) library recipes")
        }
    }

    static func makeRecipe(from seed: SeedRecipe) -> Recipe {
        let nutrition = seed.nutrition.map {
            NutritionFacts(
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbohydrateGrams: $0.carbohydrateGrams,
                fatGrams: $0.fatGrams,
                fibreGrams: $0.fibreGrams,
                source: .estimate
            )
        }

        let recipe = Recipe(
            title: seed.title,
            summary: seed.summary,
            prepTimeMinutes: seed.prepTimeMinutes,
            cookTimeMinutes: seed.cookTimeMinutes,
            servings: max(1, seed.servings),
            difficulty: RecipeDifficulty(rawValue: seed.difficulty) ?? .easy,
            cuisine: seed.cuisine?.isEmpty == false ? seed.cuisine : nil,
            tags: seed.tags,
            equipment: seed.equipment,
            steps: seed.steps,
            origin: .library,
            nutrition: nutrition
        )

        recipe.ingredients = seed.ingredients.enumerated().map { index, ingredient in
            RecipeIngredient(
                name: ingredient.name,
                quantity: ingredient.quantity ?? 0,
                unit: MeasurementUnit.from(rawValue: ingredient.unit ?? MeasurementUnit.piece.rawValue),
                preparation: ingredient.preparation,
                isOptional: ingredient.isOptional ?? false,
                substitutions: ingredient.substitutions ?? [],
                sortOrder: index
            )
        }
        return recipe
    }
}
