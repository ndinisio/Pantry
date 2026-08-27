import SwiftUI

/// Where in the kitchen an item lives. Optional throughout the app — an item with no
/// location is perfectly valid and shows up under "Unassigned".
enum StorageLocation: String, CaseIterable, Identifiable, Codable, Sendable {
    case pantry
    case fridge
    case freezer
    case cupboard
    case counter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pantry: return String(localized: "Pantry")
        case .fridge: return String(localized: "Fridge")
        case .freezer: return String(localized: "Freezer")
        case .cupboard: return String(localized: "Cupboard")
        case .counter: return String(localized: "Counter")
        }
    }

    var symbolName: String {
        switch self {
        case .pantry: return "cabinet"
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .cupboard: return "door.left.hand.closed"
        case .counter: return "square.split.bottomrightquarter"
        }
    }

    static func from(rawValue: String?) -> StorageLocation? {
        guard let rawValue else { return nil }
        return StorageLocation(rawValue: rawValue)
    }
}
