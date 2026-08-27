import SwiftUI
import SwiftData

/// Everything that isn't part of the daily loop.
///
/// A plain grouped list, which is what iOS uses for settings, rather than a designed
/// "profile" screen. Preferences are here because they change rarely; the things a
/// person does often live in the four tabs to the left.
struct MoreView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MealPlanView()
                    } label: {
                        Label(String(localized: "Meal Plan"), systemImage: "calendar")
                    }
                    NavigationLink {
                        InventoryInsightsView()
                    } label: {
                        Label(String(localized: "Pantry Insights"), systemImage: "chart.bar")
                    }
                }

                Section {
                    NavigationLink {
                        PreferencesView()
                    } label: {
                        Label(String(localized: "Cooking Preferences"), systemImage: "fork.knife")
                    }
                    NavigationLink {
                        NutritionSettingsView()
                    } label: {
                        Label(String(localized: "Nutrition"), systemImage: "chart.pie")
                    }
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label(String(localized: "Reminders"), systemImage: "bell")
                    }
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label(String(localized: "Intelligence"), systemImage: "sparkles")
                    }
                }

                Section {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        Label(String(localized: "Data & Sample Content"), systemImage: "externaldrive")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label(String(localized: "About Pantry"), systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(Text("More"))
        }
    }
}

/// The shape of the pantry, described locally and — optionally — by a model.
struct InventoryInsightsView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]

    @State private var state: AIState<AIResponses.InventoryAnalysis> = .idle
    @State private var task: Task<Void, Never>?

    private var categoryCounts: [(category: FoodCategory, count: Int)] {
        FoodCategory.allCases.compactMap { category in
            let count = items.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
        .sorted { $0.count > $1.count }
    }

    private var readyCount: Int {
        RecipeMatcher.match(
            recipes: recipes.browsable,
            inventory: items,
            query: RecipeQuery(appetite: .useWhatIHave),
            preferences: appEnvironment.preferences,
            limit: 500
        ).count
    }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Items")) {
                    Text("\(items.count)").monospacedDigit()
                }
                LabeledContent(String(localized: "Recipes you can cook now")) {
                    Text("\(readyCount)").monospacedDigit()
                }
            } header: {
                Text("At a Glance")
            }

            if !categoryCounts.isEmpty {
                Section(String(localized: "By Category")) {
                    ForEach(categoryCounts, id: \.category) { entry in
                        LabeledContent {
                            Text("\(entry.count)").monospacedDigit()
                        } label: {
                            Label(entry.category.name, systemImage: entry.category.symbolName)
                        }
                    }
                }
            }

            Section {
                switch state {
                case .idle:
                    Button(action: analyse) {
                        Label(String(localized: "Describe My Pantry"), systemImage: "sparkles")
                    }
                    .disabled(items.isEmpty)
                case .loading:
                    AIProgressView(
                        message: String(localized: "Reading your pantry…"),
                        cancel: { task?.cancel(); state = .idle }
                    )
                case .loaded(let result):
                    Text(result.value.summary)
                    if !result.value.strengths.isEmpty {
                        LabeledContent(String(localized: "Strong on")) {
                            Text(result.value.strengths.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if !result.value.gaps.isEmpty {
                        LabeledContent(String(localized: "Thin on")) {
                            Text(result.value.gaps.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                case .failed(let error):
                    AIErrorView(error: error, retry: analyse)
                }
            } header: {
                Text("Analysis")
            } footer: {
                if case .loaded(let result) = state {
                    AIProvenanceFooter(
                        providerName: result.providerName,
                        wasOnDevice: result.wasOnDevice,
                        isSample: result.isSample
                    )
                }
            }
        }
        .navigationTitle(Text("Pantry Insights"))
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nothing to Analyse"), systemImage: "chart.bar")
                } description: {
                    Text("Add some food and Pantry can tell you what your kitchen is set up for.")
                }
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func analyse() {
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let result = try await appEnvironment.aiService.inventoryAnalysis(
                    inventory: items,
                    preferences: appEnvironment.preferences
                )
                guard !Task.isCancelled else { return }
                state = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                state = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }
}

#Preview {
    MoreView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
