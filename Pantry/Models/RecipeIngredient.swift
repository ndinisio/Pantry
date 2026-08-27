import Foundation
import SwiftData

/// One line in a recipe's ingredient list.
///
/// Quantities are stored numerically so servings can be scaled without re-parsing text.
@Model
final class RecipeIngredient {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 0
    var unitRaw: String = MeasurementUnit.piece.rawValue
    /// Optional preparation note, e.g. "finely chopped".
    var preparation: String?
    /// A recipe still works without this — used to soften "you need" lists.
    var isOptional: Bool = false
    /// Suggested stand-ins, offered when the user doesn't have the ingredient.
    var substitutions: [String] = []
    var sortOrder: Int = 0

    var recipe: Recipe?

    init(
        name: String,
        quantity: Double = 0,
        unit: MeasurementUnit = .piece,
        preparation: String? = nil,
        isOptional: Bool = false,
        substitutions: [String] = [],
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.preparation = preparation
        self.isOptional = isOptional
        self.substitutions = substitutions
        self.sortOrder = sortOrder
    }

    var unit: MeasurementUnit {
        get { MeasurementUnit.from(rawValue: unitRaw) }
        set { unitRaw = newValue.rawValue }
    }

    var matchKey: String { IngredientNormaliser.key(for: name) }

    /// "200 g rice, rinsed"
    var displayDescription: String {
        displayDescription(scaledBy: 1)
    }

    func displayDescription(scaledBy factor: Double) -> String {
        var text = name
        if quantity > 0 {
            text = QuantityFormatter.string(quantity: quantity * factor, unit: unit) + " " + name
        }
        if let preparation, !preparation.isEmpty {
            text += ", " + preparation
        }
        return text
    }
}
