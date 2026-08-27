import Foundation

/// Guesses a food's category from its name so the user does not have to pick one on
/// the fast path. Wrong guesses are cheap — the category is one tap to change — but a
/// forced picker on every add is not.
enum CategoryGuesser {

    private static let table: [FoodCategory: [String]] = [
        .produce: ["apple", "banana", "orange", "lemon", "lime", "tomato", "potato", "onion",
                   "garlic", "carrot", "spinach", "lettuce", "cucumber", "pepper", "broccoli",
                   "mushroom", "avocado", "strawberr", "blueberr", "raspberr", "grape", "salad",
                   "courgette", "zucchini", "aubergine", "cabbage", "celery", "leek", "herb",
                   "basil", "parsley", "coriander", "ginger", "banana", "melon", "peach", "pear",
                   "spring onion", "scallion", "kale", "corn", "bean sprout"],
        .dairy: ["milk", "cheese", "cheddar", "yogurt", "yoghurt", "butter", "cream", "egg",
                 "mozzarella", "parmesan", "feta", "halloumi", "mascarpone", "ricotta", "custard",
                 "creme fraiche", "brie", "gouda"],
        .meatAndFish: ["chicken", "beef", "pork", "lamb", "bacon", "sausage", "ham", "turkey",
                       "mince", "steak", "fish", "salmon", "tuna", "cod", "prawn", "shrimp",
                       "haddock", "sardine", "anchovy", "mackerel", "duck", "chorizo"],
        .grains: ["rice", "pasta", "spaghetti", "penne", "noodle", "bread", "flour", "oat",
                  "cereal", "quinoa", "couscous", "tortilla", "wrap", "bagel", "cracker",
                  "barley", "bulgur", "polenta", "pitta", "baguette"],
        .cannedAndJarred: ["can", "tin", "chickpea", "lentil", "kidney bean", "baked bean",
                           "sweetcorn", "coconut milk", "passata", "chopped tomato", "olive",
                           "gherkin", "jar", "pickle", "tuna can"],
        .frozen: ["frozen", "ice cream", "peas", "ice"],
        .snacks: ["crisp", "chip", "chocolate", "biscuit", "cookie", "nut", "popcorn", "sweet",
                  "candy", "bar", "pretzel", "cake"],
        .drinks: ["water", "juice", "coffee", "tea", "soda", "cola", "beer", "wine", "squash",
                  "lemonade", "smoothie", "kombucha"],
        .saucesAndCondiments: ["sauce", "ketchup", "mayonnaise", "mayo", "mustard", "vinegar",
                               "oil", "soy", "sriracha", "pesto", "honey", "jam", "syrup",
                               "dressing", "tahini", "harissa", "marmalade", "stock", "gravy"],
        .spices: ["salt", "pepper", "paprika", "cumin", "cinnamon", "oregano", "thyme",
                  "rosemary", "chilli flake", "curry powder", "turmeric", "nutmeg", "spice",
                  "bay leaf", "cardamom", "seasoning"]
    ]

    static func category(for name: String) -> FoodCategory {
        let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        // Frozen wins over the underlying food: "frozen peas" belongs in the freezer.
        if key.contains("frozen") || key.contains("ice cream") { return .frozen }

        var best: (category: FoodCategory, length: Int)?
        for (category, keywords) in table {
            for keyword in keywords where key.contains(keyword) {
                // Prefer the most specific keyword so "coconut milk" beats "milk".
                if best == nil || keyword.count > best!.length {
                    best = (category, keyword.count)
                }
            }
        }
        return best?.category ?? .other
    }

    /// A sensible default unit for a food, so quantity entry starts in the right place.
    static func unit(for name: String) -> MeasurementUnit {
        let category = category(for: name)
        let key = name.lowercased()
        if key.contains("milk") || key.contains("juice") || key.contains("water") || key.contains("oil") {
            return .millilitre
        }
        switch category {
        case .meatAndFish, .grains, .spices: return .gram
        case .drinks: return .millilitre
        case .cannedAndJarred: return .can
        case .produce, .dairy, .snacks, .frozen, .saucesAndCondiments, .other: return .piece
        }
    }
}
