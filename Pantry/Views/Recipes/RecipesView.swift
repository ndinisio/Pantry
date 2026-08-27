import SwiftUI
import SwiftData

/// The recipe library.
///
/// Organised the way a cook thinks rather than by where a recipe came from: what is
/// ready right now, what is quick, what is nearly there, what has been saved. Sections
/// only appear when they have something in them, and each is capped with a "See All"
/// so the screen stays scannable however large the library gets.
struct RecipesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var isPresentingWhatCanIMake = false
    @State private var path = NavigationPath()

    private static let sectionLimit = 4

    private var allMatches: [RecipeMatch] {
        RecipeMatcher.match(
            recipes: browsableRecipes,
            inventory: items,
            query: RecipeQuery(appetite: .happyToShop),
            preferences: appEnvironment.preferences,
            useSoonWindowDays: appEnvironment.preferences.useSoonWindowDays,
            limit: 500
        )
    }

    /// Generated recipes the user hasn't saved stay out of the library — they are
    /// reachable from the suggestion that produced them until they are saved or swept.
    private var browsableRecipes: [Recipe] {
        recipes.filter { $0.origin != .generated || $0.isSaved }
    }

    private var searchResults: [RecipeMatch] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return allMatches.filter { match in
            match.recipe.title.localizedCaseInsensitiveContains(query)
                || match.recipe.summary.localizedCaseInsensitiveContains(query)
                || match.recipe.cuisine?.localizedCaseInsensitiveContains(query) == true
                || match.recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var readyNow: [RecipeMatch] { allMatches.filter(\.canCookNow) }
    private var quick: [RecipeMatch] { allMatches.filter { $0.recipe.totalTimeMinutes <= 20 } }
    private var almostThere: [RecipeMatch] {
        allMatches.filter { $0.missingIngredients.count == 1 }
    }
    private var usesExpiring: [RecipeMatch] {
        allMatches.filter { !$0.expiringItemsUsed.isEmpty }
    }
    private var saved: [Recipe] {
        browsableRecipes.filter(\.isSaved).sorted { $0.title < $1.title }
    }
    private var recentlyCooked: [Recipe] {
        browsableRecipes
            .filter { $0.lastCookedDate != nil }
            .sorted { ($0.lastCookedDate ?? .distantPast) > ($1.lastCookedDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !searchText.isEmpty {
                    searchResultsList
                } else if browsableRecipes.isEmpty {
                    emptyState
                } else {
                    browse
                }
            }
            .navigationTitle(Text("Recipes"))
            .searchable(text: $searchText, prompt: Text("Search recipes and ingredients"))
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: RecipeCollection.self) { collection in
                RecipeCollectionView(collection: collection, matches: matches(for: collection))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingWhatCanIMake = true
                    } label: {
                        Label(String(localized: "What Can I Make?"), systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: $isPresentingWhatCanIMake) {
                NavigationStack { WhatCanIMakeView() }
            }
            .onChange(of: appEnvironment.pendingRoute) { _, _ in handlePendingRoute() }
            .onAppear { handlePendingRoute() }
        }
    }

    // MARK: - Browse

    private var browse: some View {
        List {
            collectionSection(.forYou, matches: allMatches)
            collectionSection(.usesExpiring, matches: usesExpiring)
            collectionSection(.quick, matches: quick)
            collectionSection(.almostThere, matches: almostThere)

            if !saved.isEmpty {
                Section {
                    ForEach(saved.prefix(Self.sectionLimit)) { recipe in
                        NavigationLink(value: recipe) {
                            PlainRecipeRow(recipe: recipe)
                        }
                    }
                    if saved.count > Self.sectionLimit {
                        NavigationLink(value: RecipeCollection.saved) {
                            Text("See all \(saved.count)")
                        }
                    }
                } header: {
                    Text(RecipeCollection.saved.title)
                }
            }

            if !recentlyCooked.isEmpty {
                Section {
                    ForEach(recentlyCooked.prefix(Self.sectionLimit)) { recipe in
                        NavigationLink(value: recipe) {
                            PlainRecipeRow(recipe: recipe)
                        }
                    }
                } header: {
                    Text(RecipeCollection.recentlyCooked.title)
                }
            }

            Section {
                NavigationLink(value: RecipeCollection.all) {
                    Label(String(localized: "All Recipes"), systemImage: "list.bullet")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func collectionSection(_ collection: RecipeCollection, matches: [RecipeMatch]) -> some View {
        if !matches.isEmpty {
            Section {
                ForEach(matches.prefix(Self.sectionLimit)) { match in
                    NavigationLink(value: match.recipe) {
                        RecipeRow(match: match)
                    }
                }
                if matches.count > Self.sectionLimit {
                    NavigationLink(value: collection) {
                        Text("See all \(matches.count)")
                    }
                }
            } header: {
                Text(collection.title)
            } footer: {
                if let footer = collection.footer {
                    Text(footer)
                }
            }
        }
    }

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(searchResults) { match in
                        NavigationLink(value: match.recipe) {
                            RecipeRow(match: match)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Recipes Yet"), systemImage: "book")
        } description: {
            Text("Pantry comes with a starter library. If it's missing, reinstall it from More → Recipe Library.")
        }
    }

    private func matches(for collection: RecipeCollection) -> [RecipeMatch] {
        switch collection {
        case .forYou, .all: return allMatches
        case .readyNow: return readyNow
        case .quick: return quick
        case .almostThere: return almostThere
        case .usesExpiring: return usesExpiring
        case .saved:
            let savedIDs = Set(saved.map(\.id))
            return allMatches.filter { savedIDs.contains($0.recipeID) }
        case .recentlyCooked:
            let cookedIDs = Set(recentlyCooked.map(\.id))
            return allMatches.filter { cookedIDs.contains($0.recipeID) }
        case .tagged(let tag):
            return allMatches.filter { $0.recipe.tags.contains(tag) }
        }
    }

    /// Opens a recipe that something outside the app asked for — a widget tap, an
    /// intent, or a suggestion the user just materialised.
    private func handlePendingRoute() {
        guard let route = appEnvironment.takePendingRoute(matching: { route in
            if case .recipe = route { return true }
            return false
        }) else { return }

        guard case .recipe(let id) = route,
              let recipe = recipes.first(where: { $0.id == id }) else { return }

        searchText = ""
        isPresentingWhatCanIMake = false
        path.append(recipe)
    }
}

/// A named group of recipes, used both as a section heading and as a navigation value.
enum RecipeCollection: Hashable {
    case forYou
    case readyNow
    case quick
    case almostThere
    case usesExpiring
    case saved
    case recentlyCooked
    case all
    case tagged(String)

    var title: String {
        switch self {
        case .forYou: return String(localized: "For You")
        case .readyNow: return String(localized: "Ready Now")
        case .quick: return String(localized: "Quick")
        case .almostThere: return String(localized: "Almost Everything I Have")
        case .usesExpiring: return String(localized: "Uses Food to Be Used Soon")
        case .saved: return String(localized: "Saved")
        case .recentlyCooked: return String(localized: "Recently Cooked")
        case .all: return String(localized: "All Recipes")
        case .tagged(let tag): return RecipeTag(rawValue: tag)?.name ?? tag.capitalized
        }
    }

    var footer: String? {
        switch self {
        case .almostThere: return String(localized: "One ingredient short.")
        case .usesExpiring: return String(localized: "These use something close to its date.")
        default: return nil
        }
    }
}

/// The "See All" destination for any collection.
struct RecipeCollectionView: View {
    var collection: RecipeCollection
    var matches: [RecipeMatch]

    var body: some View {
        List {
            ForEach(matches) { match in
                NavigationLink(value: match.recipe) {
                    RecipeRow(match: match)
                }
            }
        }
        .navigationTitle(collection.title)
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nothing Here Yet"), systemImage: "book")
                } description: {
                    Text("Add more to your pantry and this will fill up.")
                }
            }
        }
    }
}

#Preview {
    RecipesView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
