import Foundation

/// Builds the compact description of the user's kitchen that goes into a prompt.
///
/// The whole database is never sent. The context is capped, ordered by relevance
/// (things expiring first, then pinned, then everything else) and contains no
/// identifiers, photos, dates of purchase or anything else the model doesn't need.
/// That keeps requests small and cheap, and keeps the user's data exposure minimal.
struct AIContextBuilder {

    /// Upper bound on inventory lines. Enough to reason about a real kitchen without
    /// sending hundreds of items on every request.
    var maxInventoryLines = 40
    var maxExpiringLines = 8

    func context(
        inventory: [PantryItem],
        preferences: PreferenceSnapshot,
        now: Date = .now
    ) -> String {
        var sections: [String] = []

        let stocked = inventory.filter { $0.quantity > 0 }
        let ranked = stocked.sorted { lhs, rhs in
            let l = lhs.expirationDate ?? .distantFuture
            let r = rhs.expirationDate ?? .distantFuture
            if l != r { return l < r }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.name < rhs.name
        }

        if ranked.isEmpty {
            sections.append("Inventory:\n- (empty)")
        } else {
            let lines = ranked.prefix(maxInventoryLines).map { item -> String in
                var line = "- \(item.name): \(item.quantityDescription)"
                if item.isOpened { line += " (opened)" }
                return line
            }
            var block = "Inventory:\n" + lines.joined(separator: "\n")
            if ranked.count > maxInventoryLines {
                block += "\n- (+\(ranked.count - maxInventoryLines) more items not listed)"
            }
            sections.append(block)
        }

        let expiring = ranked
            .filter {
                ExpirationCalculator
                    .freshness(for: $0.expirationDate, useSoonWindowDays: preferences.useSoonWindowDays, now: now)
                    .isNoteworthy
            }
            .prefix(maxExpiringLines)

        if !expiring.isEmpty {
            let lines = expiring.map { item -> String in
                let when = ExpirationCalculator.relativeDescription(for: item.expirationDate, now: now) ?? "soon"
                return "- \(item.name): \(when.lowercased())"
            }
            sections.append("Expiring soon:\n" + lines.joined(separator: "\n"))
        }

        var preferenceLines: [String] = []
        if preferences.dietaryStyle != .noPreference {
            preferenceLines.append("- Diet: \(preferences.dietaryStyle.name)")
        }
        if !preferences.allergies.isEmpty {
            preferenceLines.append("- Must avoid (allergy or intolerance): \(preferences.allergies.joined(separator: ", "))")
        }
        if !preferences.dislikedFoods.isEmpty {
            preferenceLines.append("- Dislikes: \(preferences.dislikedFoods.joined(separator: ", "))")
        }
        if !preferences.favouriteCuisines.isEmpty {
            preferenceLines.append("- Enjoys: \(preferences.favouriteCuisines.joined(separator: ", "))")
        }
        preferenceLines.append("- Usual servings: \(preferences.defaultServings)")
        preferenceLines.append("- Comfortable with: \(preferences.skillLevel.name.lowercased()) recipes")
        preferenceLines.append("- Time available: up to \(preferences.maxCookingTimeMinutes) minutes")
        preferenceLines.append("- Budget: \(preferences.budgetPreference.name.lowercased())")
        sections.append("Preferences:\n" + preferenceLines.joined(separator: "\n"))

        if !preferences.equipment.isEmpty {
            let lines = preferences.equipment.map { "- \($0.name)" }
            sections.append("Equipment:\n" + lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Estimated token cost of a context block, used to keep requests within budget.
    /// A rough four-characters-per-token rule is plenty for this purpose.
    static func estimatedTokens(in text: String) -> Int {
        max(1, text.count / 4)
    }
}
