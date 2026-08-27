import Foundation
import SwiftData

/// One thing the user owns.
///
/// Every field beyond `name` is optional by design: the fast path for adding food is
/// name → quantity → done. Enum-backed fields are persisted as `String` so the schema
/// survives new cases without a migration.
@Model
final class PantryItem {
    /// Stable identity used by widgets, App Intents and deep links.
    var id: UUID = UUID()

    var name: String = ""
    var categoryRaw: String = FoodCategory.other.rawValue
    var quantity: Double = 1
    var unitRaw: String = MeasurementUnit.piece.rawValue

    var expirationDate: Date?
    var dateAdded: Date = Date.now
    var lastModified: Date = Date.now

    var locationRaw: String?
    var brand: String?
    var notes: String?

    var isPinned: Bool = false
    var isOpened: Bool = false
    var openedDate: Date?

    var barcode: String?
    @Attribute(.externalStorage) var photoData: Data?

    /// Optional nutrition per 100 g / 100 ml, or per piece for countable units.
    var nutritionData: Data?

    init(
        name: String,
        category: FoodCategory = .other,
        quantity: Double = 1,
        unit: MeasurementUnit = .piece,
        expirationDate: Date? = nil,
        location: StorageLocation? = nil,
        brand: String? = nil,
        notes: String? = nil,
        isPinned: Bool = false,
        isOpened: Bool = false,
        barcode: String? = nil,
        photoData: Data? = nil,
        nutrition: NutritionFacts? = nil,
        dateAdded: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.expirationDate = expirationDate
        self.locationRaw = location?.rawValue
        self.brand = brand
        self.notes = notes
        self.isPinned = isPinned
        self.isOpened = isOpened
        self.openedDate = isOpened ? dateAdded : nil
        self.barcode = barcode
        self.photoData = photoData
        self.dateAdded = dateAdded
        self.lastModified = dateAdded
        self.nutritionData = nutrition.flatMap { try? JSONEncoder().encode($0) }
    }

    // MARK: - Typed accessors

    var category: FoodCategory {
        get { FoodCategory.from(rawValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var unit: MeasurementUnit {
        get { MeasurementUnit.from(rawValue: unitRaw) }
        set { unitRaw = newValue.rawValue }
    }

    var location: StorageLocation? {
        get { StorageLocation.from(rawValue: locationRaw) }
        set { locationRaw = newValue?.rawValue }
    }

    var nutrition: NutritionFacts? {
        get {
            guard let nutritionData else { return nil }
            return try? JSONDecoder().decode(NutritionFacts.self, from: nutritionData)
        }
        set {
            nutritionData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Normalised name used for ingredient matching. Not shown to the user.
    var matchKey: String { IngredientNormaliser.key(for: name) }

    // MARK: - Derived state

    var freshness: FreshnessState {
        ExpirationCalculator.freshness(for: expirationDate)
    }

    var daysUntilExpiration: Int? {
        ExpirationCalculator.daysUntil(expirationDate)
    }

    var isRunningLow: Bool {
        quantity <= (unit.isCountable ? 1 : unit.stepIncrement)
    }

    /// "500 g", "6 pcs" — the compact form used in lists.
    var quantityDescription: String {
        QuantityFormatter.string(quantity: quantity, unit: unit)
    }

    /// Spoken form, e.g. "500 grams".
    var accessibleQuantityDescription: String {
        QuantityFormatter.accessibleString(quantity: quantity, unit: unit)
    }

    func touch() { lastModified = .now }
}
