import Foundation
import WidgetKit

/// A small, flat summary of the pantry that a widget can read without opening the
/// SwiftData store.
///
/// Widgets get a tight memory budget and a short window to render. Writing a handful
/// of values to a shared container is cheaper and more reliable than standing up the
/// whole model stack in an extension.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var totalItems: Int
    var expiringSoon: Int
    var shoppingCount: Int
    /// Names of the first few items to use, for the "use soon" widget.
    var useSoonNames: [String]
    /// The best recipe the user could cook right now, if there is one.
    var suggestedRecipeTitle: String?
    var suggestedRecipeMinutes: Int?
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        totalItems: 0,
        expiringSoon: 0,
        shoppingCount: 0,
        useSoonNames: [],
        suggestedRecipeTitle: nil,
        suggestedRecipeMinutes: nil,
        updatedAt: .distantPast
    )
}

/// Reads and writes the snapshot in the shared app group container.
///
/// The app group has to be added in Xcode under Signing & Capabilities for both the
/// app and the widget target — it cannot be set up from source. Until it is, this
/// falls back to standard defaults so the app never fails because a widget isn't
/// configured; the widget then shows its placeholder.
enum WidgetSnapshotStore {

    /// Change this if you use a different app group identifier.
    static let appGroupIdentifier = "group.com.pantryapp.Pantry"
    static let widgetKind = "PantryStatusWidget"

    private static let key = "widget.snapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// True when the app group is actually configured. Surfaced so the app can tell
    /// the user why widgets are not updating rather than failing silently.
    static var isAppGroupConfigured: Bool {
        UserDefaults(suiteName: appGroupIdentifier) != nil
    }

    static func read() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
