import SwiftUI

/// The shelf a pantry item belongs on.
///
/// Stored on `PantryItem` as a raw `String` rather than as an enum so that adding,
/// renaming or reordering cases never requires a SwiftData migration. Unknown raw
/// values decode to `.other` instead of failing.
enum FoodCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case produce
    case dairy
    case meatAndFish
    case grains
    case cannedAndJarred
    case frozen
    case snacks
    case drinks
    case saucesAndCondiments
    case spices
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .produce: return String(localized: "Produce")
        case .dairy: return String(localized: "Dairy")
        case .meatAndFish: return String(localized: "Meat & Fish")
        case .grains: return String(localized: "Grains")
        case .cannedAndJarred: return String(localized: "Canned & Jarred")
        case .frozen: return String(localized: "Frozen")
        case .snacks: return String(localized: "Snacks")
        case .drinks: return String(localized: "Drinks")
        case .saucesAndCondiments: return String(localized: "Sauces & Condiments")
        case .spices: return String(localized: "Spices")
        case .other: return String(localized: "Other")
        }
    }

    var symbolName: String {
        switch self {
        case .produce: return "carrot"
        case .dairy: return "drop"
        case .meatAndFish: return "fish"
        case .grains: return "laurel.leading"
        case .cannedAndJarred: return "cylinder"
        case .frozen: return "snowflake"
        case .snacks: return "birthday.cake"
        case .drinks: return "cup.and.saucer"
        case .saucesAndCondiments: return "drop.triangle"
        case .spices: return "leaf"
        case .other: return "shippingbox"
        }
    }

    /// Tint used for the category glyph. Kept to system colours so Dark Mode and
    /// Increase Contrast are handled by the system rather than by hand-picked hexes.
    var tint: Color {
        switch self {
        case .produce: return .green
        case .dairy: return .blue
        case .meatAndFish: return .pink
        case .grains: return .brown
        case .cannedAndJarred: return .gray
        case .frozen: return .cyan
        case .snacks: return .orange
        case .drinks: return .teal
        case .saucesAndCondiments: return .red
        case .spices: return .mint
        case .other: return .secondary
        }
    }

    /// The default shelf life used when the user does not supply an expiration date
    /// and asks Pantry to estimate one. `nil` means "no sensible default".
    var typicalShelfLifeDays: Int? {
        switch self {
        case .produce: return 7
        case .dairy: return 10
        case .meatAndFish: return 3
        case .grains: return 365
        case .cannedAndJarred: return 730
        case .frozen: return 120
        case .snacks: return 90
        case .drinks: return 180
        case .saucesAndCondiments: return 180
        case .spices: return 730
        case .other: return nil
        }
    }

    static func from(rawValue: String) -> FoodCategory {
        FoodCategory(rawValue: rawValue) ?? .other
    }
}
