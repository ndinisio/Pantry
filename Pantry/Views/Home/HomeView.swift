import SwiftUI
import SwiftData
import TipKit

/// The cooking dashboard.
///
/// Contextual rather than comprehensive: sections appear only when they have something
/// to say. An empty pantry shows one thing to do; a full pantry with nothing expiring
/// doesn't show a "Use Soon" heading with nothing under it. The greeting is the
/// navigation title, so the screen starts with content rather than with a header.
struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]
    @Query(filter: #Predicate<ShoppingItem> { !$0.isPurchased }) private var shoppingItems: [ShoppingItem]

    @State private var isPresentingWhatCanIMake = false
    @State private var isPresentingQuickAdd = false

    private let useSoonTip = UseSoonTip()

    private var windowDays: Int { appEnvironment.preferences.useSoonWindowDays }
    private var service: InventoryService { InventoryService(context: modelContext) }

    private var needingAttention: [PantryItem] {
        items
            .filter { $0.quantity > 0 }
            .filter {
                ExpirationCalculator
                    .freshness(for: $0.expirationDate, useSoonWindowDays: windowDays)
                    .isNoteworthy
            }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }

    private var tonight: [RecipeMatch] {
        guard !items.isEmpty else { return [] }
        var query = RecipeQuery()
        query.appetite = .useWhatIHave
        query.maxTotalMinutes = appEnvironment.preferences.maxCookingTimeMinutes
        let ready = RecipeMatcher.match(
            recipes: recipes,
            inventory: items,
            query: query,
            preferences: appEnvironment.preferences,
            useSoonWindowDays: windowDays,
            limit: 3
        )
        guard ready.isEmpty else { return ready }

        // Nothing is cookable outright — show the closest options instead of nothing.
        var fallback = RecipeQuery()
        fallback.appetite = .almostNoShopping
        return RecipeMatcher.match(
            recipes: recipes,
            inventory: items,
            query: fallback,
            preferences: appEnvironment.preferences,
            useSoonWindowDays: windowDays,
            limit: 3
        )
    }

    private var recentlyAdded: [PantryItem] {
        Array(items.sorted { $0.dateAdded > $1.dateAdded }.prefix(4))
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    dashboard
                }
            }
            .navigationTitle(Greeting.current())
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: PantryItem.self) { PantryItemDetailView(item: $0) }
            .sheet(isPresented: $isPresentingWhatCanIMake) {
                NavigationStack { WhatCanIMakeView() }
            }
            .sheet(isPresented: $isPresentingQuickAdd) {
                QuickAddView()
            }
            .onChange(of: appEnvironment.pendingRoute) { _, _ in handlePendingRoute() }
            .onAppear { handlePendingRoute() }
            .task {
                if !needingAttention.isEmpty {
                    await UseSoonTip.hasExpiringItems.donate()
                }
            }
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        List {
            if appEnvironment.isUsingTemporaryStore {
                Section {
                    Label(
                        String(localized: "Pantry couldn't open its saved data, so changes in this session won't be kept."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    isPresentingWhatCanIMake = true
                } label: {
                    Label(String(localized: "What Can I Make?"), systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityHint(Text("Finds recipes from what's in your pantry"))
            }

            if !needingAttention.isEmpty {
                Section {
                    TipView(useSoonTip)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                    ForEach(needingAttention.prefix(4)) { item in
                        NavigationLink(value: item) {
                            PantryItemRow(item: item, useSoonWindowDays: windowDays)
                        }
                    }
                    if needingAttention.count > 4 {
                        NavigationLink {
                            UseSoonListView()
                        } label: {
                            Text("See all \(needingAttention.count)")
                        }
                    }
                } header: {
                    Text("Use Soon")
                } footer: {
                    Text("Dates are a guide. Use your judgement about what's still good.")
                }
            }

            if !tonight.isEmpty {
                Section {
                    ForEach(tonight) { match in
                        NavigationLink(value: match.recipe) {
                            RecipeRow(match: match)
                        }
                    }
                } header: {
                    Text(tonight.first?.canCookNow == true ? "Cook Tonight" : "Nearly There")
                }
            }

            Section {
                LabeledContent(String(localized: "Items")) {
                    Text("\(items.count)")
                        .monospacedDigit()
                }
                if !needingAttention.isEmpty {
                    LabeledContent(String(localized: "To use soon")) {
                        Text("\(needingAttention.count)")
                            .monospacedDigit()
                    }
                }
                if !shoppingItems.isEmpty {
                    LabeledContent(String(localized: "On your list")) {
                        Text("\(shoppingItems.count)")
                            .monospacedDigit()
                    }
                }
                ForEach(locationCounts, id: \.location) { entry in
                    LabeledContent {
                        Text("\(entry.count)")
                            .monospacedDigit()
                    } label: {
                        Label(entry.location.name, systemImage: entry.location.symbolName)
                    }
                }
            } header: {
                Text("Your Pantry")
            }

            if !recentlyAdded.isEmpty {
                Section {
                    ForEach(recentlyAdded) { item in
                        NavigationLink(value: item) {
                            PantryItemRow(item: item, useSoonWindowDays: windowDays)
                        }
                    }
                } header: {
                    Text("Recently Added")
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingQuickAdd = true
                } label: {
                    Label(String(localized: "Add Food"), systemImage: "plus")
                }
            }
        }
    }

    private var locationCounts: [(location: StorageLocation, count: Int)] {
        StorageLocation.allCases.compactMap { location in
            let count = items.filter { $0.location == location }.count
            return count > 0 ? (location, count) : nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Nothing in Your Pantry Yet"), systemImage: "cabinet")
        } description: {
            Text("Add the food you already have and Pantry can start finding meals for you.")
        } actions: {
            Button {
                isPresentingQuickAdd = true
            } label: {
                Text("Add Food")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func handlePendingRoute() {
        guard let route = appEnvironment.takePendingRoute(matching: { route in
            if case .whatCanIMake = route { return true }
            if case .useSoon = route { return true }
            return false
        }) else { return }

        if case .whatCanIMake = route {
            isPresentingWhatCanIMake = true
        }
    }
}

/// The time-of-day greeting used as the Home title.
enum Greeting {
    static func current(date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<5: return String(localized: "Good evening")
        case 5..<12: return String(localized: "Good morning")
        case 12..<18: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }
}

/// Every item that needs using, when Home's short list isn't enough.
struct UseSoonListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.expirationDate)]) private var items: [PantryItem]

    private var windowDays: Int { appEnvironment.preferences.useSoonWindowDays }

    private var needingAttention: [PantryItem] {
        items.filter {
            $0.quantity > 0 && ExpirationCalculator
                .freshness(for: $0.expirationDate, useSoonWindowDays: windowDays)
                .isNoteworthy
        }
    }

    var body: some View {
        List {
            ForEach(needingAttention) { item in
                NavigationLink(value: item) {
                    PantryItemRow(item: item, useSoonWindowDays: windowDays)
                }
            }
        }
        .navigationTitle(Text("Use Soon"))
        .overlay {
            if needingAttention.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nothing Needs Using"), systemImage: "checkmark.circle")
                } description: {
                    Text("Nothing in your pantry is close to its date.")
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
