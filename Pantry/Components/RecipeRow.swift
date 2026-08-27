import SwiftUI

/// A recipe in a list, with what it needs from the user's own pantry.
///
/// The availability line is the point of the row — "Ready with your pantry" is the
/// answer to the question the user actually has.
struct RecipeRow: View {
    var match: RecipeMatch
    var showsCoverage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(match.recipe.title)
                .font(.headline)
                .lineLimit(2)

            if !match.recipe.summary.isEmpty {
                Text(match.recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Label(
                    String(localized: "\(match.recipe.totalTimeMinutes) min"),
                    systemImage: "clock"
                )
                .labelStyle(.titleAndIcon)

                if showsCoverage {
                    Label(
                        match.availabilityDescription,
                        systemImage: match.canCookNow ? "checkmark.circle.fill" : "cart"
                    )
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(match.canCookNow ? Color.accentColor : Color.secondary)
                }

                if !match.expiringItemsUsed.isEmpty {
                    Label(String(localized: "Uses food to be used soon"), systemImage: "clock.badge")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [match.recipe.title]
        parts.append(String(localized: "\(match.recipe.totalTimeMinutes) minutes"))
        parts.append(match.availabilityDescription)
        if !match.expiringItemsUsed.isEmpty {
            let names = match.expiringItemsUsed.map(\.name).joined(separator: ", ")
            parts.append(String(localized: "Uses \(names), which needs using soon"))
        }
        return parts.joined(separator: ", ")
    }
}

/// A recipe with no pantry context — used for saved recipes, where "what you're
/// missing" is not the question being asked.
struct PlainRecipeRow: View {
    var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 10) {
                Label(String(localized: "\(recipe.totalTimeMinutes) min"), systemImage: "clock")
                Text(recipe.difficulty.name)
                if recipe.timesCooked > 0 {
                    Label(String(localized: "Cooked \(recipe.timesCooked) times"), systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
