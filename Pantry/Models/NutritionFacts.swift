import Foundation

/// Optional nutrition, always attributed to a source so the UI can be honest about
/// what is measured and what is estimated. Stored as a Codable value on the model.
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
    var fatGrams: Double?
    var fibreGrams: Double?
    var source: Source

    init(
        calories: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        fatGrams: Double? = nil,
        fibreGrams: Double? = nil,
        source: Source = .estimate
    ) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fibreGrams = fibreGrams
        self.source = source
    }

    var isEmpty: Bool {
        calories == nil && proteinGrams == nil && carbohydrateGrams == nil
            && fatGrams == nil && fibreGrams == nil
    }

    var isEstimated: Bool { source == .estimate }
}
