import Foundation
import SwiftData

/// Something to consider buying.
///
/// Shopping is not a plain list: every entry carries a priority and a plain-language
/// reason, so the user can see *why* Pantry is suggesting it.
@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = FoodCategory.other.rawValue
    var quantity: Double = 1
    var unitRaw: String = MeasurementUnit.piece.rawValue
    var priorityRaw: String = ShoppingPriority.needed.rawValue
    /// One short sentence explaining the suggestion, shown under the name.
    var reason: String?
    var notes: String?
    var isPurchased: Bool = false
    var purchasedDate: Date?
    var dateAdded: Date = Date.now
    /// True when Pantry proposed the item rather than the user typing it.
    var isSuggested: Bool = false
    /// Title of the recipe that created the need, when there is one.
    var sourceRecipeTitle: String?

    init(
        name: String,
        category: FoodCategory = .other,
        quantity: Double = 1,
        unit: MeasurementUnit = .piece,
        priority: ShoppingPriority = .needed,
        reason: String? = nil,
        notes: String? = nil,
        isSuggested: Bool = false,
        sourceRecipeTitle: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.priorityRaw = priority.rawValue
        self.reason = reason
        self.notes = notes
        self.isSuggested = isSuggested
        self.sourceRecipeTitle = sourceRecipeTitle
        self.dateAdded = .now
    }

    var category: FoodCategory {
        get { FoodCategory.from(rawValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var unit: MeasurementUnit {
        get { MeasurementUnit.from(rawValue: unitRaw) }
        set { unitRaw = newValue.rawValue }
    }

    var priority: ShoppingPriority {
        get { ShoppingPriority(rawValue: priorityRaw) ?? .needed }
        set { priorityRaw = newValue.rawValue }
    }

    var matchKey: String { IngredientNormaliser.key(for: name) }

    var quantityDescription: String {
        QuantityFormatter.string(quantity: quantity, unit: unit)
    }

    /// Converts a purchased entry into inventory.
    func makePantryItem() -> PantryItem {
        PantryItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            expirationDate: ExpirationCalculator.suggestedExpiration(for: category),
            notes: notes
        )
    }
}

/// Why an item is on the list. Ordered from most to least urgent.
enum ShoppingPriority: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Required by something the user has actually planned to cook.
    case needed
    /// Would meaningfully expand what the user can make.
    case useful
    /// Nice to have.
    case optional

    var id: String { rawValue }

    var name: String {
        switch self {
        case .needed: return String(localized: "Needed")
        case .useful: return String(localized: "Useful")
        case .optional: return String(localized: "Optional")
        }
    }

    var footnote: String {
        switch self {
        case .needed: return String(localized: "For meals you've planned")
        case .useful: return String(localized: "Unlocks more meals")
        case .optional: return String(localized: "Nice to have")
        }
    }

    var symbolName: String {
        switch self {
        case .needed: return "exclamationmark.circle"
        case .useful: return "sparkles"
        case .optional: return "circle.dashed"
        }
    }

    var sortIndex: Int {
        switch self {
        case .needed: return 0
        case .useful: return 1
        case .optional: return 2
        }
    }
}
