import Foundation

/// A nutrient Pantry can show.
///
/// The set is deliberately small — the ones on a UK/EU nutrition label plus fibre.
/// Which of them actually appear is the user's choice, because a person watching
/// protein and a person watching salt want to look at different rows, and showing all
/// eight to everyone would make the panel noise rather than information.
enum Nutrient: String, CaseIterable, Identifiable, Codable, Sendable {
    case calories
    case protein
    case carbohydrate
    case sugar
    case fat
    case saturatedFat
    case fibre
    case salt

    var id: String { rawValue }

    var name: String {
        switch self {
        case .calories: return String(localized: "Calories")
        case .protein: return String(localized: "Protein")
        case .carbohydrate: return String(localized: "Carbohydrate")
        case .sugar: return String(localized: "Sugars")
        case .fat: return String(localized: "Fat")
        case .saturatedFat: return String(localized: "Saturates")
        case .fibre: return String(localized: "Fibre")
        case .salt: return String(localized: "Salt")
        }
    }

    /// Unit suffix. Calories carry none — "520" reads better than "520 kcal" in a row
    /// already labelled Calories.
    var unit: String? {
        switch self {
        case .calories: return nil
        case .salt: return "g"
        default: return "g"
        }
    }

    /// Spoken form, so VoiceOver says "twelve grams" rather than "twelve g".
    var accessibleUnit: String? {
        switch self {
        case .calories: return String(localized: "calories")
        default: return String(localized: "grams")
        }
    }

    /// Shown under a nutrient in Settings, where the distinction is worth a sentence.
    var footnote: String? {
        switch self {
        case .saturatedFat: return String(localized: "Part of total fat")
        case .sugar: return String(localized: "Part of total carbohydrate")
        case .salt: return String(localized: "Not sodium — the label figure")
        default: return nil
        }
    }

    /// What a nutrition panel shows unless the user says otherwise: the four on the
    /// front of most packaging, plus fibre.
    static let defaultSelection: [Nutrient] = [.calories, .protein, .carbohydrate, .fat, .fibre]

    static func from(rawValues: [String]) -> [Nutrient] {
        // Preserve label order rather than the order they happen to be stored in.
        allCases.filter { rawValues.contains($0.rawValue) }
    }
}

/// Optional nutrition, always attributed to a source so the UI can be honest about
/// what is measured and what is estimated. Stored as a Codable value on the model.
///
/// Every field is optional and decodes from older stored data unchanged, so adding a
/// nutrient never invalidates what is already saved.
struct NutritionFacts: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Typed in by the user or read from a product label.
        case product
        /// Produced by a language model. Never presented as precise.
        case estimate
    }

    var calories: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var sugarGrams: Double?
    var fatGrams: Double?
    var saturatedFatGrams: Double?
    var fibreGrams: Double?
    var saltGrams: Double?
    var source: Source

    init(
        calories: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        sugarGrams: Double? = nil,
        fatGrams: Double? = nil,
        saturatedFatGrams: Double? = nil,
        fibreGrams: Double? = nil,
        saltGrams: Double? = nil,
        source: Source = .estimate
    ) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.sugarGrams = sugarGrams
        self.fatGrams = fatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.fibreGrams = fibreGrams
        self.saltGrams = saltGrams
        self.source = source
    }

    /// The stored figure for a nutrient, or `nil` when this recipe or product doesn't
    /// carry one. A missing value is never rendered as zero — "no data" and "none of it"
    /// are different claims.
    func value(for nutrient: Nutrient) -> Double? {
        switch nutrient {
        case .calories: return calories
        case .protein: return proteinGrams
        case .carbohydrate: return carbohydrateGrams
        case .sugar: return sugarGrams
        case .fat: return fatGrams
        case .saturatedFat: return saturatedFatGrams
        case .fibre: return fibreGrams
        case .salt: return saltGrams
        }
    }

    /// Formatted for display, e.g. "12 g" or "520".
    func displayValue(for nutrient: Nutrient) -> String? {
        guard let value = value(for: nutrient) else { return nil }
        let amount = QuantityFormatter.number(value)
        guard let unit = nutrient.unit else { return amount }
        return "\(amount) \(unit)"
    }

    /// Spoken form for VoiceOver.
    func accessibleValue(for nutrient: Nutrient) -> String? {
        guard let value = value(for: nutrient) else { return nil }
        let amount = QuantityFormatter.number(value)
        guard let unit = nutrient.accessibleUnit else { return amount }
        return "\(amount) \(unit)"
    }

    /// Whether any of the given nutrients has a figure worth showing.
    func hasAnyValue(among nutrients: [Nutrient]) -> Bool {
        nutrients.contains { value(for: $0) != nil }
    }

    var isEmpty: Bool {
        !hasAnyValue(among: Nutrient.allCases)
    }

    var isEstimated: Bool { source == .estimate }
}
