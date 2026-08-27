import SwiftUI
import SwiftData

/// "What can I make?" — the app's central question.
///
/// Results from the local matcher appear immediately, with no network and no waiting,
/// and update as the filters change. Asking a model for fresh ideas is an extra step
/// the user takes deliberately, not a gate in front of the answer.
struct WhatCanIMakeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]

    @State private var timeLimit: TimeLimit = .any
    @State private var mealType: MealType?
    @State private var appetite: ShoppingAppetite = .useWhatIHave
    @State private var maxDifficulty: RecipeDifficulty?
    @State private var mustUse: Set<String> = []
    @State private var avoid: Set<String> = []
    @State private var aiState: AIState<[AIResponses.RecipeSuggestion]> = .idle
    @State private var generationTask: Task<Void, Never>?
    @State private var isPresentingUseUpPicker = false

    /// Set when opened from an item's detail screen.
    var preselectedItemName: String?

    private var query: RecipeQuery {
        var query = RecipeQuery()
        query.maxTotalMinutes = timeLimit.minutes
        query.mealType = mealType
        query.maxDifficulty = maxDifficulty
        query.appetite = appetite
        query.mustUseKeys = mustUse
        query.avoidKeys = avoid
        return query
    }

    private var matches: [RecipeMatch] {
        RecipeMatcher.match(
            recipes: recipes,
            inventory: items,
            query: query,
            preferences: appEnvironment.preferences,
            useSoonWindowDays: appEnvironment.preferences.useSoonWindowDays,
            limit: 20
        )
    }

    var body: some View {
        List {
            filterSection

            if !mustUse.isEmpty {
                Section {
                    ForEach(Array(mustUse).sorted(), id: \.self) { key in
                        HStack {
                            Text(key.capitalized)
                            Spacer()
                            Button {
                                withAnimation { mustUse.remove(key) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(localized: "Stop using \(key)"))
                        }
                    }
                } header: {
                    Text("Using Up")
                }
            }

            resultsSection
            generatedSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("What Can I Make?"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
        .sheet(isPresented: $isPresentingUseUpPicker) {
            UseUpPicker(items: items, selection: $mustUse)
        }
        .onAppear {
            if let preselectedItemName, mustUse.isEmpty {
                mustUse = [IngredientNormaliser.key(for: preselectedItemName)]
            }
        }
        .onDisappear { generationTask?.cancel() }
    }

    // MARK: - Filters

    private var filterSection: some View {
        Section {
            Picker(String(localized: "Time"), selection: $timeLimit) {
                ForEach(TimeLimit.allCases) { limit in
                    Text(limit.name).tag(limit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "Time available"))

            Picker(String(localized: "Shopping"), selection: $appetite) {
                ForEach(ShoppingAppetite.allCases) { option in
                    Text(option.name).tag(option)
                }
            }

            Picker(String(localized: "Meal"), selection: $mealType) {
                Text("Any").tag(MealType?.none)
                ForEach(MealType.allCases) { type in
                    Label(type.name, systemImage: type.symbolName).tag(MealType?.some(type))
                }
            }

            Picker(String(localized: "Difficulty"), selection: $maxDifficulty) {
                Text("Any").tag(RecipeDifficulty?.none)
                ForEach(RecipeDifficulty.allCases) { level in
                    Text(level.name).tag(RecipeDifficulty?.some(level))
                }
            }

            Button {
                isPresentingUseUpPicker = true
            } label: {
                Label(String(localized: "Ingredients to Use Up"), systemImage: "checklist")
            }
        } header: {
            Text("Right Now")
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if matches.isEmpty {
            Section {
                ContentUnavailableView {
                    Label(String(localized: "Nothing Matches Yet"), systemImage: "fork.knife")
                } description: {
                    Text(items.isEmpty
                         ? String(localized: "Add a few things to your pantry and ideas will appear here.")
                         : String(localized: "Try allowing a bit of shopping, or more time."))
                } actions: {
                    if appetite != .happyToShop {
                        Button(String(localized: "Allow Some Shopping")) {
                            withAnimation { appetite = .almostNoShopping }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(matches) { match in
                    NavigationLink(value: match.recipe) {
                        RecipeRow(match: match)
                    }
                }
            } header: {
                Text(matches.count == 1 ? "1 Idea from Your Pantry" : "\(matches.count) Ideas from Your Pantry")
            } footer: {
                Text("From your recipe library. No network needed.")
            }
        }
    }

    // MARK: - Generated

    @ViewBuilder
    private var generatedSection: some View {
        Section {
            switch aiState {
            case .idle:
                if !appEnvironment.network.isConnected {
                    OfflineNoticeView()
                }
                Button(action: generate) {
                    Label(String(localized: "Ask for New Ideas"), systemImage: "sparkles")
                }
                .disabled(items.isEmpty)

            case .loading:
                AIProgressView(
                    message: String(localized: "Thinking about what you have…"),
                    cancel: { generationTask?.cancel(); aiState = .idle }
                )
                .listRowBackground(Color.clear)

            case .loaded(let result):
                ForEach(result.value) { suggestion in
                    Button {
                        open(suggestion)
                    } label: {
                        GeneratedSuggestionRow(suggestion: suggestion, isSample: result.isSample)
                    }
                }
                Button(action: generate) {
                    Label(String(localized: "Ask Again"), systemImage: "arrow.clockwise")
                }

            case .failed(let error):
                AIErrorView(error: error, retry: generate)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("New Ideas")
        } footer: {
            if case .loaded(let result) = aiState {
                AIProvenanceFooter(
                    providerName: result.providerName,
                    wasOnDevice: result.wasOnDevice,
                    isSample: result.isSample
                )
            } else if case .idle = aiState {
                Text("Generates recipes from your inventory and preferences.")
            }
        }
    }

    private func generate() {
        generationTask?.cancel()
        aiState = .loading
        generationTask = Task {
            do {
                let result = try await appEnvironment.aiService.suggestRecipes(
                    inventory: items,
                    preferences: appEnvironment.preferences,
                    query: query,
                    count: 3
                )
                guard !Task.isCancelled else { return }
                aiState = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                aiState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                aiState = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }

    /// Materialises a suggestion so the normal recipe screen — cooking mode, servings,
    /// shopping, sharing — works on it without a parallel implementation.
    private func open(_ suggestion: AIResponses.RecipeSuggestion) {
        let recipe = suggestion.makeRecipe()
        modelContext.insert(recipe)
        try? modelContext.save()
        appEnvironment.route(to: .recipe(recipe.id))
        dismiss()
    }
}

/// Time filter offered as a segmented control, because there are only four answers.
enum TimeLimit: String, CaseIterable, Identifiable {
    case quarterHour
    case halfHour
    case longer
    case any

    var id: String { rawValue }

    var name: String {
        switch self {
        case .quarterHour: return String(localized: "15 min")
        case .halfHour: return String(localized: "30 min")
        case .longer: return String(localized: "45+ min")
        case .any: return String(localized: "Any")
        }
    }

    var minutes: Int? {
        switch self {
        case .quarterHour: return 15
        case .halfHour: return 30
        case .longer: return nil
        case .any: return nil
        }
    }
}

/// One generated idea before it becomes a recipe.
private struct GeneratedSuggestionRow: View {
    var suggestion: AIResponses.RecipeSuggestion
    var isSample: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(suggestion.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Label(
                    String(localized: "\(suggestion.prepTimeMinutes + suggestion.cookTimeMinutes) min"),
                    systemImage: "clock"
                )
                if let missing = suggestion.missingIngredients, !missing.isEmpty {
                    Label(String(localized: "Needs \(missing.count)"), systemImage: "cart")
                } else {
                    Label(String(localized: "Ready with your pantry"), systemImage: "checkmark.circle")
                }
                if isSample {
                    Label(String(localized: "Sample"), systemImage: "hammer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Choosing which items to build a meal around.
private struct UseUpPicker: View {
    var items: [PantryItem]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    private var sorted: [PantryItem] {
        items
            .filter { $0.quantity > 0 }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sorted) { item in
                    let key = item.matchKey
                    Button {
                        if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
                    } label: {
                        HStack {
                            PantryItemRow(item: item, useSoonWindowDays: appEnvironment.preferences.useSoonWindowDays)
                            Image(systemName: selection.contains(key) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(key) ? Color.accentColor : Color.secondary)
                                .imageScale(.large)
                        }
                    }
                    .accessibilityAddTraits(selection.contains(key) ? [.isSelected] : [])
                }
            }
            .navigationTitle(Text("Use Up"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .overlay {
                if sorted.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "Nothing to Choose From"), systemImage: "cabinet")
                    } description: {
                        Text("Add something to your pantry first.")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WhatCanIMakeView()
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
