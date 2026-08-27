import Foundation

/// The shapes Pantry asks models to produce.
///
/// Nothing in the app renders free-form model prose where structure is needed. Every
/// payload here is decoded and validated before it reaches a view, and anything that
/// fails validation is treated as a failed request rather than shown.
enum AIResponses {

    // MARK: - Recipes

    struct RecipeSuggestionList: Codable {
        var recipes: [RecipeSuggestion]
    }

    struct RecipeSuggestion: Codable, Identifiable {
        var id: String { title }

        var title: String
        var description: String
        var prepTimeMinutes: Int
        var cookTimeMinutes: Int
        var servings: Int
        var difficulty: String?
        var cuisine: String?
        var tags: [String]?
        var equipment: [String]?
        var ingredients: [Ingredient]
        var steps: [String]
        var ownedIngredients: [String]?
        var missingIngredients: [String]?
        var nutritionPerServing: Nutrition?

        struct Ingredient: Codable {
            var name: String
            var quantity: Double?
            var unit: String?
            var preparation: String?
            var isOptional: Bool?
            var substitutions: [String]?
        }

        struct Nutrition: Codable {
            var calories: Double?
            var proteinGrams: Double?
            var carbohydrateGrams: Double?
            var sugarGrams: Double?
            var fatGrams: Double?
            var saturatedFatGrams: Double?
            var fibreGrams: Double?
            var saltGrams: Double?
        }

        /// Rejects payloads that decode but are not usable — an empty title, no steps,
        /// no ingredients, or nonsensical timings.
        var isUsable: Bool {
            !title.trimmingCharacters(in: .whitespaces).isEmpty
                && !ingredients.isEmpty
                && !steps.isEmpty
                && servings > 0
                && prepTimeMinutes >= 0
                && cookTimeMinutes >= 0
                && prepTimeMinutes + cookTimeMinutes < 24 * 60
        }

        func makeRecipe() -> Recipe {
            let nutrition = nutritionPerServing.map {
                NutritionFacts(
                    calories: $0.calories,
                    proteinGrams: $0.proteinGrams,
                    carbohydrateGrams: $0.carbohydrateGrams,
                    sugarGrams: $0.sugarGrams,
                    fatGrams: $0.fatGrams,
                    saturatedFatGrams: $0.saturatedFatGrams,
                    fibreGrams: $0.fibreGrams,
                    saltGrams: $0.saltGrams,
                    source: .estimate
                )
            }

            let recipe = Recipe(
                title: title,
                summary: description,
                prepTimeMinutes: prepTimeMinutes,
                cookTimeMinutes: cookTimeMinutes,
                servings: servings,
                difficulty: difficulty.flatMap(RecipeDifficulty.init(rawValue:)) ?? .easy,
                cuisine: cuisine,
                tags: tags ?? [],
                equipment: equipment ?? [],
                steps: steps,
                origin: .generated,
                nutrition: nutrition
            )
            recipe.ingredients = ingredients.enumerated().map { index, ingredient in
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

    // MARK: - Substitutions

    struct SubstitutionList: Codable {
        var ingredient: String
        var substitutions: [Substitution]

        struct Substitution: Codable, Identifiable {
            var id: String { name }
            var name: String
            /// How to swap it in, e.g. "use three quarters as much".
            var howToUse: String
            /// Whether the user already has it — filled in by the app, not the model.
            var note: String?
        }

        var isUsable: Bool { !substitutions.isEmpty }
    }

    // MARK: - Meal plan

    struct MealPlan: Codable {
        var days: [Day]

        struct Day: Codable, Identifiable {
            var id: String { date }
            /// ISO-8601 date, e.g. "2026-09-02".
            var date: String
            var mealType: String?
            var title: String
            var reason: String?
            var totalTimeMinutes: Int?
        }

        var isUsable: Bool { !days.isEmpty && days.allSatisfy { !$0.title.isEmpty } }
    }

    // MARK: - Shopping advice

    struct ShoppingAdvice: Codable {
        var summary: String
        var items: [Item]

        struct Item: Codable, Identifiable {
            var id: String { name }
            var name: String
            var priority: String?
            var reason: String
            var quantity: Double?
            var unit: String?
        }

        var isUsable: Bool { !items.isEmpty || !summary.isEmpty }
    }

    // MARK: - Inventory analysis

    struct InventoryAnalysis: Codable {
        /// Two or three sentences about the shape of the pantry.
        var summary: String
        var strengths: [String]
        var gaps: [String]

        var isUsable: Bool { !summary.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Leftovers

    struct LeftoverIdeas: Codable {
        var ideas: [Idea]

        struct Idea: Codable, Identifiable {
            var id: String { title }
            var title: String
            var description: String
            var usesIngredients: [String]?
        }

        var isUsable: Bool { !ideas.isEmpty }
    }
}
