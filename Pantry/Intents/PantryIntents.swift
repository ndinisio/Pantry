import AppIntents
import SwiftData
import Foundation

/// "What can I make?"
///
/// Answers out loud from the local matcher, so it works with no network — which is the
/// difference between a useful voice shortcut and one that says "sorry, try again".
struct WhatCanIMakeIntent: AppIntent {
    static var title: LocalizedStringResource = "What Can I Make?"
    static var description = IntentDescription(
        "Suggests meals you can cook from what's already in your pantry.",
        categoryName: "Cooking"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Allow shopping", default: false)
    var allowShopping: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = IntentStore.items()
        guard !items.isEmpty else {
            return .result(dialog: "Your pantry is empty. Add a few things and I'll find you something to cook.")
        }

        var query = RecipeQuery()
        query.appetite = allowShopping ? .almostNoShopping : .useWhatIHave

        let matches = RecipeMatcher.match(
            recipes: IntentStore.recipes(),
            inventory: items,
            query: query,
            preferences: IntentStore.preferences,
            limit: 3
        )

        guard !matches.isEmpty else {
            return .result(dialog: "Nothing quite matches right now. Opening Pantry will show you what you're closest to making.")
        }

        let titles = matches.map(\.recipe.title)
        let dialog: IntentDialog
        switch titles.count {
        case 1:
            dialog = "You could make \(titles[0])."
        case 2:
            dialog = "You could make \(titles[0]), or \(titles[1])."
        default:
            dialog = "You could make \(titles[0]), \(titles[1]), or \(titles[2])."
        }
        return .result(dialog: dialog)
    }
}

/// "What needs using?"
struct ShowExpiringItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "What Needs Using"
    static var description = IntentDescription(
        "Tells you which food in your pantry is close to its date.",
        categoryName: "Pantry"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let preferences = IntentStore.preferences
        let needing = IntentStore.items()
            .filter { $0.quantity > 0 }
            .filter {
                ExpirationCalculator
                    .freshness(for: $0.expirationDate, useSoonWindowDays: preferences.useSoonWindowDays)
                    .isNoteworthy
            }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }

        guard !needing.isEmpty else {
            return .result(dialog: "Nothing needs using right now.")
        }

        let names = needing.prefix(3).map(\.name)
        let dialog: IntentDialog
        if needing.count == 1 {
            dialog = "\(names[0]) needs using."
        } else if needing.count <= 3 {
            dialog = "\(names.joined(separator: ", ")) need using."
        } else {
            dialog = "\(names.joined(separator: ", ")) and \(needing.count - 3) more need using."
        }
        return .result(dialog: dialog)
    }
}

/// "Add milk to my pantry."
struct AddPantryItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Pantry"
    static var description = IntentDescription(
        "Adds an item to your pantry.",
        categoryName: "Pantry"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: "What did you get?")
    var name: String

    @Parameter(title: "Quantity", default: 1)
    var quantity: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't catch what to add.")
        }

        // Reuse the same parser the app uses, so "two litres of milk" spoken aloud
        // behaves exactly as it does when typed.
        let parsed = NaturalLanguageItemParser.parseFragment(trimmed.lowercased())
        let category = parsed?.category ?? CategoryGuesser.category(for: trimmed)
        let unit = parsed?.unit ?? CategoryGuesser.unit(for: trimmed)
        let itemName = parsed?.name ?? trimmed
        let amount = parsed.map { $0.quantity == 1 ? quantity : $0.quantity } ?? quantity

        let item = PantryItem(
            name: itemName,
            category: category,
            quantity: QuantityFormatter.normalise(amount, unit: unit),
            unit: unit,
            expirationDate: ExpirationCalculator.suggestedExpiration(for: category)
        )
        InventoryService(context: IntentStore.context).add([item])
        IntentStore.refreshWidgets()

        return .result(dialog: "Added \(QuantityFormatter.string(quantity: item.quantity, unit: unit)) \(itemName) to your pantry.")
    }
}

/// "Add coffee to my shopping list."
struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Shopping List"
    static var description = IntentDescription(
        "Adds something to your shopping list.",
        categoryName: "Shopping"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: "What should I add?")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't catch what to add.")
        }

        let parsed = NaturalLanguageItemParser.parseFragment(trimmed.lowercased())
        let itemName = parsed?.name ?? trimmed
        let item = ShoppingItem(
            name: itemName,
            category: parsed?.category ?? CategoryGuesser.category(for: itemName),
            quantity: parsed?.quantity ?? 1,
            unit: parsed?.unit ?? CategoryGuesser.unit(for: itemName),
            priority: .needed
        )
        IntentStore.context.insert(item)
        try? IntentStore.context.save()
        IntentStore.refreshWidgets()

        return .result(dialog: "Added \(itemName) to your shopping list.")
    }
}

/// Opens the app on the recipe suggestions, for the widget's tap target and for anyone
/// who wants the full screen rather than a spoken answer.
struct OpenWhatCanIMakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open What Can I Make"
    static var description = IntentDescription(
        "Opens Pantry and shows recipes you can cook right now.",
        categoryName: "Cooking"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
