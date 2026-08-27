import SwiftUI
import SwiftData

/// The shopping list, grouped by why something is on it.
///
/// A grocery list tells you what to buy. This one tells you why — "unlocks 4 more
/// recipes from your pantry" — which is the difference between a list and advice.
/// Buying something offers to move it straight into the pantry.
struct ShoppingView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\ShoppingItem.name)]) private var shoppingItems: [ShoppingItem]
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var pantryItems: [PantryItem]
    @Query private var recipes: [Recipe]
    @Query private var plan: [MealPlanEntry]

    @State private var searchText = ""
    @State private var isPresentingAdd = false
    @State private var purchasedPendingMove: ShoppingItem?
    @State private var adviceState: AIState<AIResponses.ShoppingAdvice> = .idle
    @State private var adviceTask: Task<Void, Never>?

    private var outstanding: [ShoppingItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return shoppingItems
            .filter { !$0.isPurchased }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var purchased: [ShoppingItem] {
        shoppingItems.filter(\.isPurchased).sorted { ($0.purchasedDate ?? .distantPast) > ($1.purchasedDate ?? .distantPast) }
    }

    private var suggestions: [ShoppingSuggestion] {
        ShoppingSuggestionEngine.suggestions(
            inventory: pantryItems,
            recipes: recipes,
            plannedRecipes: plannedRecipes,
            existingListKeys: Set(shoppingItems.map(\.matchKey)),
            preferences: appEnvironment.preferences,
            limit: 8
        )
    }

    private var plannedRecipes: [Recipe] {
        let upcoming = plan.filter { $0.date >= Calendar.current.startOfDay(for: .now) && !$0.isCooked }
        return upcoming.compactMap(\.recipe)
    }

    private var shareText: String {
        let lines = outstanding.map { "• \($0.name) — \($0.quantityDescription)" }
        return ([String(localized: "Shopping list")] + lines).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Group {
                if shoppingItems.isEmpty && suggestions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(Text("Shopping"))
            .searchable(text: $searchText, prompt: Text("Search your list"))
            .toolbar { toolbarContent }
            .sheet(isPresented: $isPresentingAdd) {
                AddShoppingItemView()
            }
            .confirmationDialog(
                Text("Add \(purchasedPendingMove?.name ?? "") to your pantry?"),
                isPresented: Binding(
                    get: { purchasedPendingMove != nil },
                    set: { if !$0 { purchasedPendingMove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Add to Pantry")) { moveToPantry() }
                Button(String(localized: "Just Tick It Off"), role: .cancel) { purchasedPendingMove = nil }
            }
            .onChange(of: appEnvironment.pendingRoute) { _, _ in
                _ = appEnvironment.takePendingRoute { route in
                    if case .shoppingList = route { return true }
                    return false
                }
            }
            .onDisappear { adviceTask?.cancel() }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(ShoppingPriority.allCases) { priority in
                let group = outstanding.filter { $0.priority == priority }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { item in
                            ShoppingItemRow(item: item) { toggle(item) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(item)
                                        try? modelContext.save()
                                    } label: {
                                        Label(String(localized: "Remove"), systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Menu {
                                        ForEach(ShoppingPriority.allCases) { option in
                                            Button {
                                                item.priority = option
                                                try? modelContext.save()
                                            } label: {
                                                Label(option.name, systemImage: option.symbolName)
                                            }
                                        }
                                    } label: {
                                        Label(String(localized: "Change Priority"), systemImage: "arrow.up.arrow.down")
                                    }
                                }
                        }
                    } header: {
                        Text(priority.name)
                    } footer: {
                        Text(priority.footnote)
                    }
                }
            }

            if !suggestions.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion) { add(suggestion) }
                    }
                } header: {
                    Text("Worth Buying")
                } footer: {
                    Text("Worked out from what's already in your pantry.")
                }
            }

            if searchText.isEmpty {
                adviceSection
            }

            if !purchased.isEmpty {
                Section {
                    ForEach(purchased) { item in
                        ShoppingItemRow(item: item) { toggle(item) }
                    }
                    Button(role: .destructive) {
                        for item in purchased { modelContext.delete(item) }
                        try? modelContext.save()
                    } label: {
                        Label(String(localized: "Clear Purchased"), systemImage: "trash")
                    }
                } header: {
                    Text(purchased.count == 1 ? "1 Purchased" : "\(purchased.count) Purchased")
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: outstanding.count)
        .overlay {
            if !searchText.isEmpty && outstanding.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private var adviceSection: some View {
        Section {
            switch adviceState {
            case .idle:
                Button(action: askForAdvice) {
                    Label(String(localized: "What Should I Buy?"), systemImage: "sparkles")
                }
                .disabled(pantryItems.isEmpty)
            case .loading:
                AIProgressView(
                    message: String(localized: "Looking at the shape of your pantry…"),
                    cancel: { adviceTask?.cancel(); adviceState = .idle }
                )
            case .loaded(let result):
                if !result.value.summary.isEmpty {
                    Text(result.value.summary)
                        .font(.subheadline)
                }
                ForEach(result.value.items) { item in
                    Button {
                        addAdvised(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(String(localized: "Add \(item.name). \(item.reason)"))
                }
            case .failed(let error):
                AIErrorView(error: error, retry: askForAdvice)
            }
        } header: {
            Text("Advice")
        } footer: {
            if case .loaded(let result) = adviceState {
                AIProvenanceFooter(
                    providerName: result.providerName,
                    wasOnDevice: result.wasOnDevice,
                    isSample: result.isSample
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Nothing to Buy"), systemImage: "cart")
        } description: {
            Text("Add something you need, or let Pantry suggest what would open up more meals.")
        } actions: {
            Button {
                isPresentingAdd = true
            } label: {
                Text("Add Item")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingAdd = true
            } label: {
                Label(String(localized: "Add Item"), systemImage: "plus")
            }
        }
        if !outstanding.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                ShareLink(item: shareText, subject: Text("Shopping list")) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ item: ShoppingItem) {
        withAnimation {
            item.isPurchased.toggle()
            item.purchasedDate = item.isPurchased ? .now : nil
            try? modelContext.save()
        }
        if item.isPurchased {
            purchasedPendingMove = item
        }
    }

    private func moveToPantry() {
        guard let item = purchasedPendingMove else { return }
        InventoryService(context: modelContext).add([item.makePantryItem()])
        modelContext.delete(item)
        try? modelContext.save()
        purchasedPendingMove = nil
    }

    private func add(_ suggestion: ShoppingSuggestion) {
        withAnimation {
            modelContext.insert(suggestion.makeShoppingItem())
            try? modelContext.save()
        }
    }

    private func addAdvised(_ item: AIResponses.ShoppingAdvice.Item) {
        let shoppingItem = ShoppingItem(
            name: item.name,
            category: CategoryGuesser.category(for: item.name),
            quantity: item.quantity ?? 1,
            unit: item.unit.map(MeasurementUnit.from(rawValue:)) ?? CategoryGuesser.unit(for: item.name),
            priority: item.priority.flatMap(ShoppingPriority.init(rawValue:)) ?? .useful,
            reason: item.reason,
            isSuggested: true
        )
        withAnimation {
            modelContext.insert(shoppingItem)
            try? modelContext.save()
        }
    }

    private func askForAdvice() {
        adviceTask?.cancel()
        adviceState = .loading
        adviceTask = Task {
            do {
                let result = try await appEnvironment.aiService.shoppingAdvice(
                    inventory: pantryItems,
                    preferences: appEnvironment.preferences
                )
                guard !Task.isCancelled else { return }
                adviceState = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                adviceState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                adviceState = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }
}

/// One line on the list. The whole row toggles, because that is the gesture people use
/// while holding a basket.
private struct ShoppingItemRow: View {
    var item: ShoppingItem
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(item.isPurchased ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(item.isPurchased ? .secondary : .primary)
                        .strikethrough(item.isPurchased, color: .secondary)
                    if let reason = item.reason, !reason.isEmpty, !item.isPurchased {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text(item.quantityDescription)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isPurchased ? [.isSelected] : [])
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(item.isPurchased ? "Marks as not bought" : "Marks as bought"))
    }

    private var accessibilityLabel: String {
        var parts = [item.name, item.quantityDescription]
        if let reason = item.reason, !reason.isEmpty { parts.append(reason) }
        if item.isPurchased { parts.append(String(localized: "Bought")) }
        return parts.joined(separator: ", ")
    }
}

/// A proposal that is not yet on the list.
private struct SuggestionRow: View {
    var suggestion: ShoppingSuggestion
    var onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                CategoryGlyph(category: suggestion.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .foregroundStyle(.primary)
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Add \(suggestion.name). \(suggestion.reason)"))
    }
}

#Preview {
    ShoppingView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
