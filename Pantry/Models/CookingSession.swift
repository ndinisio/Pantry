import Foundation
import SwiftData

/// A record of the user cooking a recipe. Drives "Recently Cooked" and gives the
/// leftovers feature something to reason about.
@Model
final class CookingSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var finishedAt: Date?
    var servingsCooked: Int = 2
    /// Names of the pantry items that were decremented, so the session is auditable.
    var consumedItemNames: [String] = []
    var leftoverNote: String?

    var recipe: Recipe?

    init(recipe: Recipe?, servingsCooked: Int) {
        self.id = UUID()
        self.recipe = recipe
        self.servingsCooked = servingsCooked
        self.startedAt = .now
    }

    var isFinished: Bool { finishedAt != nil }
}
