import SwiftUI

/// The app's top-level areas. Five, because these are the five things a person does
/// with food: see what's happening now, look at what they own, decide what to cook,
/// work out what to buy, and adjust how it all behaves.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case pantry
    case recipes
    case shopping
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .pantry: return String(localized: "Pantry")
        case .recipes: return String(localized: "Recipes")
        case .shopping: return String(localized: "Shopping")
        case .more: return String(localized: "More")
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .pantry: return "cabinet"
        case .recipes: return "book"
        case .shopping: return "cart"
        case .more: return "ellipsis"
        }
    }
}

/// Places the app can be sent from outside it — an App Intent, a widget tap, a
/// notification. Kept as one type so every entry point lands somewhere real.
enum AppRoute: Hashable {
    case whatCanIMake
    case useSoon
    case addItem
    case quickAdd
    case shoppingList
    case recipe(UUID)
    case pantryItem(UUID)

    var tab: AppTab {
        switch self {
        case .whatCanIMake, .useSoon: return .home
        case .addItem, .quickAdd, .pantryItem: return .pantry
        case .recipe: return .recipes
        case .shoppingList: return .shopping
        }
    }
}
