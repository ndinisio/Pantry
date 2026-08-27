import SwiftUI

/// A nutrition panel, showing only the nutrients the user has chosen to see.
///
/// Three rules hold here, and they are the reason this is a component rather than
/// inline rows:
///
/// - A nutrient with no figure is omitted, never rendered as zero. "No data" and "none
///   of it" are different claims and conflating them is the easiest way for a nutrition
///   panel to mislead.
/// - Estimated figures say so, every time, and are never presented as nutritional advice.
/// - If the user has turned every nutrient off, the panel disappears entirely rather
///   than showing an empty section.
struct NutritionSection: View {

    var nutrition: NutritionFacts
    var title: String
    var subtitle: String?

    @Environment(AppEnvironment.self) private var appEnvironment

    private var nutrients: [Nutrient] {
        appEnvironment.preferences.trackedNutrients
    }

    /// Only the chosen nutrients that this recipe or product actually carries.
    private var rows: [Nutrient] {
        nutrients.filter { nutrition.value(for: $0) != nil }
    }

    var body: some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { nutrient in
                    LabeledContent(nutrient.name) {
                        Text(nutrition.displayValue(for: nutrient) ?? "")
                            .monospacedDigit()
                    }
                    .accessibilityLabel(nutrient.name)
                    .accessibilityValue(nutrition.accessibleValue(for: nutrient) ?? "")
                }
            } header: {
                Text(title)
            } footer: {
                footer
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if nutrition.isEstimated {
                Text("Estimated, not measured. Treat these as a rough guide rather than nutritional advice.")
            } else if let subtitle {
                Text(subtitle)
            }
            // Say why a nutrient someone switched on is not listed, rather than leaving
            // them to wonder whether the app is broken.
            if rows.count < nutrients.count {
                Text("Only the figures this recipe provides are shown. Choose which nutrients to display in More → Nutrition.")
            }
        }
    }
}

#Preview {
    List {
        NutritionSection(
            nutrition: NutritionFacts(
                calories: 520, proteinGrams: 38, carbohydrateGrams: 62,
                fatGrams: 12, fibreGrams: 4, source: .estimate
            ),
            title: "Per Serving"
        )
        NutritionSection(
            nutrition: NutritionFacts(calories: 120, proteinGrams: 10, source: .product),
            title: "Per 100 g",
            subtitle: "From the product label."
        )
    }
    .environment(AppEnvironment())
}
