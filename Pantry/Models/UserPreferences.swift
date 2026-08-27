import Foundation
import SwiftData

/// The single preferences record. Everything here exists to make suggestions better —
/// nothing is required, and the app works fully with all of it left at its default.
@Model
final class UserPreferences {
    var id: UUID = UUID()

    // Diet
    var dietaryStyleRaw: String = DietaryStyle.noPreference.rawValue
    var allergies: [String] = []
    var dislikedFoods: [String] = []
    var favouriteCuisines: [String] = []

    // Cooking
    var defaultServings: Int = 2
    var skillLevelRaw: String = RecipeDifficulty.easy.rawValue
    var maxCookingTimeMinutes: Int = 45
    var equipment: [String] = CookingEquipment.defaultSelection.map(\.rawValue)
    var budgetPreferenceRaw: String = BudgetPreference.balanced.rawValue

    // Nutrition
    /// Which nutrients appear in nutrition panels. Empty means the panel is hidden
    /// entirely, which is a legitimate choice — nutrition is not this app's purpose.
    var trackedNutrients: [String] = Nutrient.defaultSelection.map(\.rawValue)

    // Expiry + notifications
    var useSoonWindowDays: Int = 3
    var expiryNotificationsEnabled: Bool = false
    var mealIdeaNotificationsEnabled: Bool = false
    /// Minutes from midnight for the daily reminder. 1140 = 19:00.
    var notificationTimeMinutes: Int = 1140

    // AI
    var aiEnabled: Bool = true
    var preferOnDeviceAI: Bool = true

    var lastUpdated: Date = Date.now

    init() {
        self.id = UUID()
    }

    var dietaryStyle: DietaryStyle {
        get { DietaryStyle(rawValue: dietaryStyleRaw) ?? .noPreference }
        set { dietaryStyleRaw = newValue.rawValue }
    }

    var skillLevel: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: skillLevelRaw) ?? .easy }
        set { skillLevelRaw = newValue.rawValue }
    }

    var budgetPreference: BudgetPreference {
        get { BudgetPreference(rawValue: budgetPreferenceRaw) ?? .balanced }
        set { budgetPreferenceRaw = newValue.rawValue }
    }

    var selectedEquipment: [CookingEquipment] {
        get { equipment.compactMap(CookingEquipment.init(rawValue:)) }
        set { equipment = newValue.map(\.rawValue) }
    }

    var selectedNutrients: [Nutrient] {
        get { Nutrient.from(rawValues: trackedNutrients) }
        set { trackedNutrients = newValue.map(\.rawValue) }
    }

    /// Everything the user has asked to avoid, normalised for matching.
    var avoidedIngredientKeys: Set<String> {
        Set((allergies + dislikedFoods).map { IngredientNormaliser.key(for: $0) })
    }
}

enum DietaryStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case noPreference
    case vegetarian
    case vegan
    case pescatarian
    case lowCarb
    case highProtein

    var id: String { rawValue }

    var name: String {
        switch self {
        case .noPreference: return String(localized: "No preference")
        case .vegetarian: return String(localized: "Vegetarian")
        case .vegan: return String(localized: "Vegan")
        case .pescatarian: return String(localized: "Pescatarian")
        case .lowCarb: return String(localized: "Lower carb")
        case .highProtein: return String(localized: "Higher protein")
        }
    }

    /// Tags a recipe must carry to fit this style. Empty means no constraint.
    var requiredRecipeTags: Set<String> {
        switch self {
        case .vegetarian: return [RecipeTag.vegetarian.rawValue]
        case .vegan: return [RecipeTag.vegan.rawValue]
        case .highProtein: return [RecipeTag.highProtein.rawValue]
        default: return []
        }
    }
}

enum BudgetPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case economical
    case balanced
    case generous

    var id: String { rawValue }

    var name: String {
        switch self {
        case .economical: return String(localized: "Economical")
        case .balanced: return String(localized: "Balanced")
        case .generous: return String(localized: "Generous")
        }
    }
}

enum CookingEquipment: String, CaseIterable, Identifiable, Codable, Sendable {
    case hob
    case oven
    case microwave
    case airFryer
    case blender
    case slowCooker
    case pressureCooker
    case grill

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hob: return String(localized: "Hob")
        case .oven: return String(localized: "Oven")
        case .microwave: return String(localized: "Microwave")
        case .airFryer: return String(localized: "Air fryer")
        case .blender: return String(localized: "Blender")
        case .slowCooker: return String(localized: "Slow cooker")
        case .pressureCooker: return String(localized: "Pressure cooker")
        case .grill: return String(localized: "Grill")
        }
    }

    var symbolName: String {
        switch self {
        case .hob: return "flame"
        case .oven: return "oven"
        case .microwave: return "microwave"
        case .airFryer: return "wind"
        case .blender: return "tornado"
        case .slowCooker: return "timer"
        case .pressureCooker: return "gauge.with.dots.needle.33percent"
        case .grill: return "flame.circle"
        }
    }

    static let defaultSelection: [CookingEquipment] = [.hob, .oven, .microwave]
}
