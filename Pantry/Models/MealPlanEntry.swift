import Foundation
import SwiftData

/// A meal placed on a day of the week's plan.
///
/// The plan stores a recipe reference when one exists and a title either way, so a
/// deleted recipe leaves a readable plan rather than an empty row.
@Model
final class MealPlanEntry {
    var id: UUID = UUID()
    /// Normalised to the start of the day so lookups are exact.
    var date: Date = Date.now
    var mealTypeRaw: String = MealType.dinner.rawValue
    var recipeTitle: String = ""
    var recipeID: UUID?
    var notes: String?
    var isCooked: Bool = false

    @Relationship var recipe: Recipe?

    init(
        date: Date,
        mealType: MealType = .dinner,
        recipeTitle: String,
        recipe: Recipe? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.mealTypeRaw = mealType.rawValue
        self.recipeTitle = recipeTitle
        self.recipe = recipe
        self.recipeID = recipe?.id
        self.notes = notes
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }
}

enum MealType: String, CaseIterable, Identifiable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var name: String {
        switch self {
        case .breakfast: return String(localized: "Breakfast")
        case .lunch: return String(localized: "Lunch")
        case .dinner: return String(localized: "Dinner")
        case .snack: return String(localized: "Snack")
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon"
        case .snack: return "takeoutbag.and.cup.and.straw"
        }
    }
}
