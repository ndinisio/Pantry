import Foundation
import OSLog

/// Shared logging identity. Keeping the subsystem in one place means the whole app's
/// logs can be filtered together in Console.
enum PantryLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.pantryapp.Pantry"

    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let inventory = Logger(subsystem: subsystem, category: "Inventory")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let recognition = Logger(subsystem: subsystem, category: "Recognition")
}
