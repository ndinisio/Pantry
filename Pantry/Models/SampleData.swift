import Foundation
import SwiftData

/// Realistic starter content so the app can be evaluated the moment it launches, and
/// so previews and UI tests have something to show.
///
/// Sample data is opt-in from Settings and can be removed again in one action — it is
/// never silently mixed into a pantry the user has already filled in.
enum SampleData {

    /// Marker used on notes so sample items can be identified and removed cleanly.
    static let marker = "· sample"

    static func populate(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: .now)
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
        }

        let items: [PantryItem] = [
            PantryItem(name: "Eggs", category: .dairy, quantity: 6, unit: .piece,
                       expirationDate: day(9), location: .fridge, notes: marker),
            PantryItem(name: "Chicken Breast", category: .meatAndFish, quantity: 500, unit: .gram,
                       expirationDate: day(1), location: .fridge, notes: marker),
            PantryItem(name: "Greek Yogurt", category: .dairy, quantity: 500, unit: .gram,
                       expirationDate: day(6), location: .fridge, notes: marker, isOpened: true),
            PantryItem(name: "Rice", category: .grains, quantity: 1, unit: .kilogram,
                       expirationDate: day(300), location: .cupboard, notes: marker),
            PantryItem(name: "Pasta", category: .grains, quantity: 500, unit: .gram,
                       expirationDate: day(240), location: .cupboard, notes: marker),
            PantryItem(name: "Tomatoes", category: .produce, quantity: 6, unit: .piece,
                       expirationDate: day(4), location: .counter, notes: marker),
            PantryItem(name: "Spinach", category: .produce, quantity: 200, unit: .gram,
                       expirationDate: day(2), location: .fridge, notes: marker),
            PantryItem(name: "Cheddar", category: .dairy, quantity: 250, unit: .gram,
                       expirationDate: day(21), location: .fridge, notes: marker),
            PantryItem(name: "Milk", category: .dairy, quantity: 2, unit: .litre,
                       expirationDate: day(5), location: .fridge, notes: marker),
            PantryItem(name: "Olive Oil", category: .saucesAndCondiments, quantity: 500, unit: .millilitre,
                       location: .cupboard, notes: marker),
            PantryItem(name: "Soy Sauce", category: .saucesAndCondiments, quantity: 250, unit: .millilitre,
                       location: .cupboard, notes: marker, isOpened: true),
            PantryItem(name: "Garlic", category: .produce, quantity: 1, unit: .piece,
                       expirationDate: day(28), location: .counter, notes: marker),
            PantryItem(name: "Onions", category: .produce, quantity: 4, unit: .piece,
                       expirationDate: day(20), location: .counter, notes: marker),
            PantryItem(name: "Frozen Peas", category: .frozen, quantity: 300, unit: .gram,
                       expirationDate: day(150), location: .freezer, notes: marker),
            PantryItem(name: "Strawberries", category: .produce, quantity: 250, unit: .gram,
                       expirationDate: day(1), location: .fridge, notes: marker),
            PantryItem(name: "Chopped Tomatoes", category: .cannedAndJarred, quantity: 2, unit: .can,
                       expirationDate: day(500), location: .cupboard, notes: marker),
            PantryItem(name: "Chilli Flakes", category: .spices, quantity: 1, unit: .jar,
                       location: .cupboard, notes: marker),
            PantryItem(name: "Parmesan", category: .dairy, quantity: 150, unit: .gram,
                       expirationDate: day(40), location: .fridge, notes: marker),
            PantryItem(name: "Bread", category: .grains, quantity: 1, unit: .pack,
                       expirationDate: day(3), location: .counter, notes: marker),
            PantryItem(name: "Butter", category: .dairy, quantity: 250, unit: .gram,
                       expirationDate: day(30), location: .fridge, notes: marker)
        ]

        for item in items { context.insert(item) }

        let shopping: [ShoppingItem] = [
            ShoppingItem(name: "Spring Onions", category: .produce, quantity: 1, unit: .pack,
                         priority: .needed, reason: String(localized: "Needed for Chicken Fried Rice"),
                         notes: marker, isSuggested: true, sourceRecipeTitle: "Chicken Fried Rice"),
            ShoppingItem(name: "Lemons", category: .produce, quantity: 3, unit: .piece,
                         priority: .useful, reason: String(localized: "Lifts most of the dishes you cook"),
                         notes: marker, isSuggested: true)
        ]
        for item in shopping { context.insert(item) }

        try? context.save()
    }

    /// Removes every item that carries the sample marker, leaving user content untouched.
    static func remove(context: ModelContext) {
        let itemDescriptor = FetchDescriptor<PantryItem>()
        if let items = try? context.fetch(itemDescriptor) {
            for item in items where item.notes?.contains(marker) == true {
                context.delete(item)
            }
        }
        let shoppingDescriptor = FetchDescriptor<ShoppingItem>()
        if let shopping = try? context.fetch(shoppingDescriptor) {
            for item in shopping where item.notes?.contains(marker) == true {
                context.delete(item)
            }
        }
        try? context.save()
    }

    /// True when any sample content is present.
    static func isPresent(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<PantryItem>()
        guard let items = try? context.fetch(descriptor) else { return false }
        return items.contains { $0.notes?.contains(marker) == true }
    }

    /// An in-memory container preloaded with sample content, for previews.
    ///
    /// Isolated because it reaches for `mainContext` directly. The helpers above take a
    /// context as a parameter and so stay free of any isolation of their own.
    @MainActor
    static func previewContainer() -> ModelContainer {
        let container = PantryModelContainer.makeContainer(inMemory: true)
        populate(context: container.mainContext)
        RecipeLibrary.installIfNeeded(context: container.mainContext)
        return container
    }
}
