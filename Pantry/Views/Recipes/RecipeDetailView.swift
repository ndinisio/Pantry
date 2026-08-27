import SwiftUI
import SwiftData

/// One recipe, read against the user's own pantry.
///
/// The ingredient list is the heart of this screen: each line says whether the user
/// already has it, and the missing ones can go to the shopping list in one action.
/// Changing the servings rescales the quantities in place rather than opening a sheet.
struct RecipeDetailView: View {

    @Bindable var recipe: Recipe

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query(filter: #Predicate<ShoppingItem> { !$0.isPurchased }) private var shoppingItems: [ShoppingItem]

    @State private var servings: Int
    @State private var isCooking = false
    @State private var isConfirmingCooked = false
    @State private var substitutionTarget: RecipeIngredient?
    @State private var addedToShoppingCount: Int?

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: max(1, recipe.servings))
    }

    private var service: InventoryService { InventoryService(context: modelContext) }

    private var scale: Double {
        recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1
    }

    private var index: InventoryIndex {
        InventoryIndex(items: items, useSoonWindowDays: appEnvironment.preferences.useSoonWindowDays)
    }

    private var sortedIngredients: [RecipeIngredient] {
        recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var missingIngredients: [RecipeIngredient] {
        sortedIngredients.filter { !$0.isOptional && !index.contains($0.name) }
    }

    private var alreadyOnList: Set<String> {
        Set(shoppingItems.map(\.matchKey))
    }

    var body: some View {
        List {
            summarySection
            ingredientsSection
            if !recipe.equipment.isEmpty { equipmentSection }
            stepsSection
            if let nutrition = recipe.nutrition, !nutrition.isEmpty {
                NutritionSection(
                    nutrition: nutrition,
                    title: String(localized: "Per Serving"),
                    subtitle: String(localized: "As published with this recipe.")
                )
            }
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .fullScreenCover(isPresented: $isCooking) {
            CookingModeView(recipe: recipe, servings: servings)
        }
        .sheet(item: $substitutionTarget) { ingredient in
            SubstitutionSheet(ingredient: ingredient, recipeTitle: recipe.title)
        }
        .confirmationDialog(
            Text("Mark as cooked?"),
            isPresented: $isConfirmingCooked,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Cooked — Update My Pantry")) {
                service.markCooked(recipe, servings: servings, consumeInventory: true)
            }
            Button(String(localized: "Cooked — Leave Pantry Alone")) {
                service.markCooked(recipe, servings: servings, consumeInventory: false)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Pantry can take the ingredients you used out of your inventory.")
        }
        .alert(
            Text("Added to Shopping"),
            isPresented: Binding(
                get: { addedToShoppingCount != nil },
                set: { if !$0 { addedToShoppingCount = nil } }
            )
        ) {
            Button(String(localized: "OK")) { addedToShoppingCount = nil }
        } message: {
            if let count = addedToShoppingCount {
                Text(count == 1 ? "1 item added to your shopping list." : "\(count) items added to your shopping list.")
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            if !recipe.summary.isEmpty {
                Text(recipe.summary)
                    .font(.body)
            }

            LabeledContent(String(localized: "Time")) {
                Text("\(recipe.totalTimeMinutes) min")
            }
            .accessibilityValue(Text("\(recipe.totalTimeMinutes) minutes"))

            if recipe.prepTimeMinutes > 0 && recipe.cookTimeMinutes > 0 {
                LabeledContent(String(localized: "Prep and Cook")) {
                    Text("\(recipe.prepTimeMinutes) + \(recipe.cookTimeMinutes) min")
                }
            }

            LabeledContent(String(localized: "Difficulty"), value: recipe.difficulty.name)

            Stepper(value: $servings, in: 1...20) {
                LabeledContent(String(localized: "Servings")) {
                    Text("\(servings)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .accessibilityValue(Text("\(servings) servings"))

            Button {
                isCooking = true
            } label: {
                Label(String(localized: "Start Cooking"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(recipe.steps.isEmpty)
            .listRowBackground(Color.clear)
        } footer: {
            if recipe.origin == .generated {
                Text("Generated for your pantry. Check quantities and cooking times before you rely on them.")
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(sortedIngredients) { ingredient in
                IngredientRow(
                    ingredient: ingredient,
                    scale: scale,
                    isOwned: index.contains(ingredient.name),
                    onSubstitute: { substitutionTarget = ingredient }
                )
            }

            if !missingIngredients.isEmpty {
                Button {
                    addMissingToShopping()
                } label: {
                    Label(
                        missingIngredients.count == 1
                            ? String(localized: "Add 1 Missing Item to Shopping")
                            : String(localized: "Add \(missingIngredients.count) Missing Items to Shopping"),
                        systemImage: "cart.badge.plus"
                    )
                }
            }
        } header: {
            Text("Ingredients")
        } footer: {
            if missingIngredients.isEmpty {
                Label(String(localized: "You have everything you need."), systemImage: "checkmark.circle")
            }
        }
    }

    private var equipmentSection: some View {
        Section(String(localized: "You'll Need")) {
            ForEach(recipe.equipment, id: \.self) { raw in
                if let equipment = CookingEquipment(rawValue: raw) {
                    Label(equipment.name, systemImage: equipment.symbolName)
                } else {
                    Text(raw.capitalized)
                }
            }
        }
    }

    private var stepsSection: some View {
        Section(String(localized: "Method")) {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(step)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Step \(index + 1). \(step)"))
            }
        }
    }

    private var historySection: some View {
        Section {
            if recipe.timesCooked > 0 {
                LabeledContent(String(localized: "Cooked")) {
                    Text(recipe.timesCooked == 1 ? "Once" : "\(recipe.timesCooked) times")
                }
                if let last = recipe.lastCookedDate {
                    LabeledContent(String(localized: "Last time")) {
                        Text(last.formatted(.dateTime.day().month(.abbreviated)))
                    }
                }
            }
            Button {
                isConfirmingCooked = true
            } label: {
                Label(String(localized: "Mark as Cooked"), systemImage: "checkmark.circle")
            }
        } header: {
            Text("History")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                recipe.isSaved.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    recipe.isSaved ? String(localized: "Saved") : String(localized: "Save"),
                    systemImage: recipe.isSaved ? "bookmark.fill" : "bookmark"
                )
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: recipe.shareText, subject: Text(recipe.title)) {
                Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Actions

    private func addMissingToShopping() {
        var added = 0
        for ingredient in missingIngredients where !alreadyOnList.contains(ingredient.matchKey) {
            let item = ShoppingItem(
                name: ingredient.name,
                category: CategoryGuesser.category(for: ingredient.name),
                quantity: ingredient.quantity > 0 ? ingredient.quantity * scale : 1,
                unit: ingredient.unit,
                priority: .needed,
                reason: String(localized: "Needed for \(recipe.title)"),
                isSuggested: true,
                sourceRecipeTitle: recipe.title
            )
            modelContext.insert(item)
            added += 1
        }
        try? modelContext.save()
        addedToShoppingCount = added
    }
}

/// One ingredient line, with whether the user has it and a way to swap it out.
private struct IngredientRow: View {
    var ingredient: RecipeIngredient
    var scale: Double
    var isOwned: Bool
    var onSubstitute: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: isOwned ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isOwned ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.displayDescription(scaledBy: scale))
                if ingredient.isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isOwned
                ? String(localized: "\(ingredient.displayDescription(scaledBy: scale)). In your pantry.")
                : String(localized: "\(ingredient.displayDescription(scaledBy: scale)). Not in your pantry.")
        )
        .accessibilityActions {
            Button(String(localized: "Find a substitute"), action: onSubstitute)
        }
        .contextMenu {
            Button {
                onSubstitute()
            } label: {
                Label(String(localized: "Find a Substitute"), systemImage: "arrow.triangle.swap")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onSubstitute()
            } label: {
                Label(String(localized: "Substitute"), systemImage: "arrow.triangle.swap")
            }
            .tint(.indigo)
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let recipe = (try? container.mainContext.fetch(FetchDescriptor<Recipe>()))?.first
        ?? Recipe(title: "Preview Recipe")

    return NavigationStack {
        RecipeDetailView(recipe: recipe)
    }
    .environment(AppEnvironment())
    .modelContainer(container)
}
