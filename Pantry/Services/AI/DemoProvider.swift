import Foundation

/// A stand-in used only when the developer explicitly turns it on, so the whole app can
/// be exercised without any credential or network.
///
/// It is never a silent fallback. `AIService` only reaches for it when the Developer
/// setting is enabled, and every result it produces is labelled in the UI as a sample
/// so nothing invented is ever mistaken for a real answer.
struct DemoProvider: AIProvider {

    let name = String(localized: "Sample responses")

    /// Small delay so loading states can actually be seen and reviewed.
    var latency: Duration = .milliseconds(700)

    func isAvailable() async -> Bool { true }

    func generate(_ request: AIRequest) async throws -> AIRawResponse {
        try await Task.sleep(for: latency)
        try Task.checkCancellation()
        return AIRawResponse(text: payload(for: request.kind), providerName: name, wasOnDevice: true)
    }

    private func payload(for kind: AIRequestKind) -> String {
        switch kind {
        case .recipeSuggestions, .useItUp:
            return Self.recipesJSON
        case .substitutions:
            return Self.substitutionsJSON
        case .mealPlan:
            return Self.mealPlanJSON
        case .shoppingAdvice:
            return Self.shoppingJSON
        case .inventoryAnalysis:
            return Self.analysisJSON
        case .leftoverIdeas:
            return Self.leftoversJSON
        }
    }

    private static let recipesJSON = """
    {
      "recipes": [
        {
          "title": "Chicken & Spinach Rice Bowl",
          "description": "A one-pan bowl that uses up the chicken and spinach together.",
          "prepTimeMinutes": 10,
          "cookTimeMinutes": 15,
          "servings": 2,
          "difficulty": "easy",
          "cuisine": "",
          "tags": ["quick", "highProtein", "onePan"],
          "equipment": ["hob"],
          "ingredients": [
            { "name": "Chicken breast", "quantity": 300, "unit": "g" },
            { "name": "Rice", "quantity": 200, "unit": "g" },
            { "name": "Spinach", "quantity": 100, "unit": "g" },
            { "name": "Garlic", "quantity": 2, "unit": "piece" },
            { "name": "Soy sauce", "quantity": 20, "unit": "ml" }
          ],
          "steps": [
            "Cook the rice.",
            "Fry the chicken with the garlic until golden.",
            "Wilt the spinach into the pan.",
            "Fold through the rice and finish with soy sauce."
          ],
          "ownedIngredients": ["Chicken breast", "Rice", "Spinach", "Garlic", "Soy sauce"],
          "missingIngredients": [],
          "nutritionPerServing": { "calories": 520, "proteinGrams": 42, "carbohydrateGrams": 58, "fatGrams": 11, "fibreGrams": 3 }
        },
        {
          "title": "Tomato & Cheddar Frittata",
          "description": "Eggs, tomatoes and the end of a block of cheddar.",
          "prepTimeMinutes": 5,
          "cookTimeMinutes": 20,
          "servings": 2,
          "difficulty": "easy",
          "cuisine": "Italian",
          "tags": ["vegetarian", "highProtein", "onePan"],
          "equipment": ["hob", "grill"],
          "ingredients": [
            { "name": "Eggs", "quantity": 6, "unit": "piece" },
            { "name": "Tomatoes", "quantity": 3, "unit": "piece" },
            { "name": "Cheddar", "quantity": 80, "unit": "g" },
            { "name": "Onions", "quantity": 1, "unit": "piece" }
          ],
          "steps": [
            "Soften the onion in an ovenproof pan.",
            "Add the tomatoes and cook for two minutes.",
            "Pour in the beaten eggs and scatter over the cheddar.",
            "Finish under a hot grill until puffed and set."
          ],
          "ownedIngredients": ["Eggs", "Tomatoes", "Cheddar", "Onions"],
          "missingIngredients": [],
          "nutritionPerServing": { "calories": 430, "proteinGrams": 30, "carbohydrateGrams": 9, "fatGrams": 30, "fibreGrams": 2 }
        }
      ]
    }
    """

    private static let substitutionsJSON = """
    {
      "ingredient": "Butter",
      "substitutions": [
        { "name": "Olive oil", "howToUse": "Use about three quarters as much — it will taste greener." },
        { "name": "Greek yogurt", "howToUse": "Works in baking; use half the weight and reduce the other liquid." }
      ]
    }
    """

    private static let mealPlanJSON = """
    {
      "days": [
        { "date": "2026-01-01", "mealType": "dinner", "title": "Chicken Fried Rice", "reason": "Uses the chicken before its date.", "totalTimeMinutes": 25 },
        { "date": "2026-01-02", "mealType": "dinner", "title": "Pasta Arrabbiata", "reason": "Store cupboard only.", "totalTimeMinutes": 20 },
        { "date": "2026-01-03", "mealType": "dinner", "title": "Baked Eggs in Tomato Sauce", "reason": "Uses the second tin of tomatoes.", "totalTimeMinutes": 25 }
      ]
    }
    """

    private static let shoppingJSON = """
    {
      "summary": "You are well set up for pasta and rice dinners but light on protein. A couple of additions would open up most of the week.",
      "items": [
        { "name": "Chicken thighs", "priority": "useful", "reason": "You already have rice, soy sauce and peas — this turns them into four more dinners.", "quantity": 500, "unit": "g" },
        { "name": "Lemons", "priority": "optional", "reason": "Lifts the yoghurt and fish dishes you already cook.", "quantity": 3, "unit": "piece" }
      ]
    }
    """

    private static let analysisJSON = """
    {
      "summary": "This is a strong store cupboard: rice, pasta, tinned tomatoes and sauces cover a lot of ground. Fresh protein is the thin part, and a few things in the fridge want using in the next couple of days.",
      "strengths": ["Rice and pasta", "Tinned tomatoes", "Good sauces"],
      "gaps": ["Fresh protein", "Green vegetables"]
    }
    """

    private static let leftoversJSON = """
    {
      "ideas": [
        { "title": "Fried rice", "description": "Half an onion and cooked chicken are most of a fried rice already.", "usesIngredients": ["Onions", "Chicken breast", "Rice"] },
        { "title": "Quick soup", "description": "Simmer the onion with stock and the chicken, and finish with any greens.", "usesIngredients": ["Onions", "Chicken breast"] }
      ]
    }
    """
}
