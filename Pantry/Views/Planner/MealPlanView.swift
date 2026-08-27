import SwiftUI
import SwiftData

/// The weekly plan.
///
/// Optional by design — the app is complete without it. When it is used, a plan feeds
/// the shopping list: anything a planned meal needs and the pantry lacks becomes a
/// "Needed" item with the meal named as the reason.
struct MealPlanView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\MealPlanEntry.date)]) private var entries: [MealPlanEntry]
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]

    @State private var weekStart: Date = Calendar.current.startOfDay(for: .now)
    @State private var planState: AIState<AIResponses.MealPlan> = .idle
    @State private var planTask: Task<Void, Never>?
    @State private var dayForPicker: Date?

    private let dayCount = 7

    private var days: [Date] {
        (0..<dayCount).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(days, id: \.self) { day in
                    DayRow(
                        date: day,
                        entry: entry(for: day),
                        onChoose: { dayForPicker = day },
                        onClear: { clear(day) }
                    )
                }
            } header: {
                Text("This Week")
            } footer: {
                Text("Anything a planned meal needs shows up on your shopping list as Needed.")
            }

            Section {
                switch planState {
                case .idle:
                    Button(action: generatePlan) {
                        Label(String(localized: "Plan My Week"), systemImage: "sparkles")
                    }
                    .disabled(items.isEmpty)
                case .loading:
                    AIProgressView(
                        message: String(localized: "Working out a week from what you have…"),
                        cancel: { planTask?.cancel(); planState = .idle }
                    )
                case .loaded(let result):
                    ForEach(result.value.days) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title).font(.headline)
                            if let reason = day.reason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Button(action: applyGeneratedPlan) {
                        Label(String(localized: "Use This Plan"), systemImage: "checkmark.circle")
                    }
                    Button(action: generatePlan) {
                        Label(String(localized: "Try Again"), systemImage: "arrow.clockwise")
                    }
                case .failed(let error):
                    AIErrorView(error: error, retry: generatePlan)
                }
            } header: {
                Text("Suggestions")
            } footer: {
                if case .loaded(let result) = planState {
                    AIProvenanceFooter(
                        providerName: result.providerName,
                        wasOnDevice: result.wasOnDevice,
                        isSample: result.isSample
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Meal Plan"))
        .sheet(item: Binding(
            get: { dayForPicker.map(DayIdentifier.init(date:)) },
            set: { if $0 == nil { dayForPicker = nil } }
        )) { day in
            PlanDayPicker(date: day.date) { recipe in
                assign(recipe, to: day.date)
            }
        }
        .onDisappear { planTask?.cancel() }
    }

    private func entry(for date: Date) -> MealPlanEntry? {
        let start = Calendar.current.startOfDay(for: date)
        return entries.first { Calendar.current.isDate($0.date, inSameDayAs: start) }
    }

    private func assign(_ recipe: Recipe, to date: Date) {
        clear(date)
        let entry = MealPlanEntry(date: date, mealType: .dinner, recipeTitle: recipe.title, recipe: recipe)
        modelContext.insert(entry)
        try? modelContext.save()
        dayForPicker = nil
    }

    private func clear(_ date: Date) {
        guard let existing = entry(for: date) else { return }
        modelContext.delete(existing)
        try? modelContext.save()
    }

    /// Matches generated titles back onto real recipes where possible, and keeps the
    /// title alone where not, so a plan is never half-empty because of a name mismatch.
    private func applyGeneratedPlan() {
        guard let plan = planState.value else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for day in plan.days {
            guard let date = formatter.date(from: day.date) else { continue }
            clear(date)
            let recipe = recipes.first { $0.title.localizedCaseInsensitiveCompare(day.title) == .orderedSame }
            let entry = MealPlanEntry(
                date: date,
                mealType: day.mealType.flatMap(MealType.init(rawValue:)) ?? .dinner,
                recipeTitle: day.title,
                recipe: recipe,
                notes: day.reason
            )
            modelContext.insert(entry)
        }
        try? modelContext.save()
        planState = .idle
    }

    private func generatePlan() {
        planTask?.cancel()
        planState = .loading
        planTask = Task {
            do {
                let result = try await appEnvironment.aiService.mealPlan(
                    startDate: weekStart,
                    days: dayCount,
                    inventory: items,
                    preferences: appEnvironment.preferences
                )
                guard !Task.isCancelled else { return }
                planState = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                planState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                planState = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }

    private struct DayIdentifier: Identifiable {
        var date: Date
        var id: TimeInterval { date.timeIntervalSince1970 }
    }
}

/// One day in the plan.
private struct DayRow: View {
    var date: Date
    var entry: MealPlanEntry?
    var onChoose: () -> Void
    var onClear: () -> Void

    private var weekday: String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(date.formatted(.dateTime.day()))
                        .font(.headline)
                        .monospacedDigit()
                }
                .frame(width: 40)
                .accessibilityHidden(true)

                if let entry {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.recipeTitle)
                            .foregroundStyle(.primary)
                        if let notes = entry.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Text("Nothing planned")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text("Chooses a meal for this day"))
        .swipeActions(edge: .trailing) {
            if entry != nil {
                Button(role: .destructive, action: onClear) {
                    Label(String(localized: "Clear"), systemImage: "trash")
                }
            }
        }
    }

    private var accessibilityLabel: String {
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let entry else { return String(localized: "\(day), nothing planned") }
        return String(localized: "\(day), \(entry.recipeTitle)")
    }
}

/// Choosing a recipe for one day, ranked by what the pantry can already cover.
private struct PlanDayPicker: View {
    var date: Date
    var onSelect: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]
    @State private var searchText = ""

    private var matches: [RecipeMatch] {
        let all = RecipeMatcher.match(
            recipes: recipes.browsable,
            inventory: items,
            query: RecipeQuery(appetite: .happyToShop),
            preferences: appEnvironment.preferences,
            limit: 200
        )
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.recipe.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches) { match in
                    Button {
                        onSelect(match.recipe)
                    } label: {
                        RecipeRow(match: match)
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text("Search recipes"))
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MealPlanView()
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
