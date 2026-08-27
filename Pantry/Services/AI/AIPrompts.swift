import Foundation

/// Every prompt the app sends, in one file.
///
/// Prompts are treated as product copy: they set the tone of what comes back, so they
/// live together where they can be read and revised as a set rather than scattered
/// through view code.
enum AIPrompts {

    /// Shared rules applied to every structured request.
    private static let jsonRules = """
        Reply with a single JSON object and nothing else. No prose before or after it, \
        no markdown code fences. Use only the keys described. If you cannot answer, \
        return the object with empty arrays rather than inventing content.
        """

    private static let cookVoice = """
        You are the cooking assistant inside Pantry, an app that tracks what someone \
        has in their kitchen. Write like a capable friend who cooks: plain, warm, \
        specific, never breathless. Use British English. Never claim an ingredient is \
        in the pantry unless it appears in the inventory you were given.
        """

    // MARK: - Recipe suggestions

    static func recipeSuggestions(context: String, count: Int, query: RecipeQuery, servings: Int) -> AIRequest {
        var constraints: [String] = []
        if let minutes = query.maxTotalMinutes {
            constraints.append("Total time must be \(minutes) minutes or less.")
        }
        if let mealType = query.mealType {
            constraints.append("These are ideas for \(mealType.name.lowercased()).")
        }
        if let difficulty = query.maxDifficulty {
            constraints.append("Keep them no harder than \(difficulty.name.lowercased()).")
        }
        switch query.appetite {
        case .useWhatIHave:
            constraints.append("Use only ingredients in the inventory, plus salt, pepper, oil and water.")
        case .almostNoShopping:
            constraints.append("Each recipe may need at most two ingredients that are not in the inventory.")
        case .happyToShop:
            constraints.append("A few extra ingredients are fine, but favour what is already there.")
        }
        if !query.mustUseKeys.isEmpty {
            constraints.append("Every recipe must use: \(query.mustUseKeys.joined(separator: ", ")).")
        }
        if !query.avoidKeys.isEmpty {
            constraints.append("Do not use: \(query.avoidKeys.joined(separator: ", ")).")
        }

        let prompt = """
            \(context)

            Suggest \(count) recipes for \(servings) servings.

            \(constraints.joined(separator: " "))

            Prioritise anything listed as expiring soon.

            \(jsonRules)

            Shape:
            {
              "recipes": [
                {
                  "title": "string",
                  "description": "one sentence",
                  "prepTimeMinutes": 0,
                  "cookTimeMinutes": 0,
                  "servings": 0,
                  "difficulty": "easy" | "medium" | "involved",
                  "cuisine": "string or null",
                  "tags": ["quick", "highProtein", "vegetarian", "vegan", "onePan", "comfort", "light"],
                  "equipment": ["hob", "oven", "microwave", "airFryer", "blender", "slowCooker", "pressureCooker", "grill"],
                  "ingredients": [
                    { "name": "string", "quantity": 0, "unit": "g|kg|ml|L|oz|lb|piece|pack|can|bottle|jar|box|serving",
                      "preparation": "string or null", "isOptional": false, "substitutions": ["string"] }
                  ],
                  "steps": ["string"],
                  "ownedIngredients": ["names taken from the inventory"],
                  "missingIngredients": ["names not in the inventory"],
                  "nutritionPerServing": { "calories": 0, "proteinGrams": 0, "carbohydrateGrams": 0, "sugarGrams": 0,
                                           "fatGrams": 0, "saturatedFatGrams": 0, "fibreGrams": 0, "saltGrams": 0 }
                }
              ]
            }
            """

        return AIRequest(
            kind: .recipeSuggestions,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 2400,
            temperature: 0.7
        )
    }

    // MARK: - Use it up

    static func useItUp(context: String, itemNames: [String], servings: Int) -> AIRequest {
        let prompt = """
            \(context)

            These need using: \(itemNames.joined(separator: ", ")).

            Suggest three recipes for \(servings) servings that use them, in order of how \
            well they use up what is listed. Prefer recipes needing nothing extra.

            \(jsonRules)

            Use the same shape as a recipe suggestion list: { "recipes": [ ... ] }
            """

        return AIRequest(
            kind: .useItUp,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 2000,
            temperature: 0.6
        )
    }

    // MARK: - Substitutions

    static func substitutions(context: String, ingredient: String, recipeTitle: String?) -> AIRequest {
        let inRecipe = recipeTitle.map { " while making \($0)" } ?? ""
        let prompt = """
            \(context)

            The cook has no \(ingredient)\(inRecipe). Suggest up to four stand-ins, \
            strongly favouring things in the inventory above. Say how to use each one, \
            including any change in quantity.

            \(jsonRules)

            Shape:
            {
              "ingredient": "\(ingredient)",
              "substitutions": [
                { "name": "string", "howToUse": "one sentence" }
              ]
            }
            """

        return AIRequest(
            kind: .substitutions,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 700,
            temperature: 0.4
        )
    }

    // MARK: - Meal plan

    static func mealPlan(context: String, startDate: Date, days: Int, servings: Int) -> AIRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dates = (0..<days).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: startDate)
        }.map(formatter.string(from:))

        let prompt = """
            \(context)

            Plan dinner for these dates: \(dates.joined(separator: ", ")). \(servings) servings each.

            Use what is in the pantry first, schedule anything expiring soon in the \
            earliest days, and vary the meals across the week. Give a short reason for each day.

            \(jsonRules)

            Shape:
            {
              "days": [
                { "date": "YYYY-MM-DD", "mealType": "dinner", "title": "string",
                  "reason": "one short sentence", "totalTimeMinutes": 0 }
              ]
            }
            """

        return AIRequest(
            kind: .mealPlan,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 1200,
            temperature: 0.6
        )
    }

    // MARK: - Shopping advice

    static func shoppingAdvice(context: String) -> AIRequest {
        let prompt = """
            \(context)

            Reason from this specific pantry, not from a generic shopping list. What \
            would most increase the number of good meals this person could make? \
            Suggest at most six things, each with a concrete reason that refers to what \
            they already own.

            \(jsonRules)

            Shape:
            {
              "summary": "two sentences about the shape of this pantry",
              "items": [
                { "name": "string", "priority": "needed" | "useful" | "optional",
                  "reason": "one sentence referring to what they already have",
                  "quantity": 0, "unit": "g|kg|ml|L|piece|pack|can|bottle|jar|box" }
              ]
            }
            """

        return AIRequest(
            kind: .shoppingAdvice,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 900,
            temperature: 0.5
        )
    }

    // MARK: - Inventory analysis

    static func inventoryAnalysis(context: String) -> AIRequest {
        let prompt = """
            \(context)

            Describe the shape of this pantry in two or three sentences — what it is \
            well set up for, and what is thin. Be concrete and refer to actual items. \
            Do not moralise about diet.

            \(jsonRules)

            Shape:
            {
              "summary": "two or three sentences",
              "strengths": ["short phrase"],
              "gaps": ["short phrase"]
            }
            """

        return AIRequest(
            kind: .inventoryAnalysis,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 500,
            temperature: 0.4
        )
    }

    // MARK: - Leftovers

    static func leftoverIdeas(context: String, leftovers: String) -> AIRequest {
        let prompt = """
            \(context)

            Left over after cooking: \(leftovers).

            Suggest three quick ways to use these up, drawing on the inventory above. \
            Keep each idea to a sentence or two.

            \(jsonRules)

            Shape:
            {
              "ideas": [
                { "title": "string", "description": "one or two sentences", "usesIngredients": ["string"] }
              ]
            }
            """

        return AIRequest(
            kind: .leftoverIdeas,
            systemPrompt: cookVoice,
            userPrompt: prompt,
            maxOutputTokens: 700,
            temperature: 0.6
        )
    }

    /// Appended when a first attempt came back unparseable. Deliberately blunt.
    static let stricterRetrySuffix = """


        Your previous reply could not be parsed. Reply with the JSON object only. \
        Start your reply with { and end it with }. No explanation, no code fence.
        """
}
