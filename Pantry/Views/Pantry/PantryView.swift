import SwiftUI
import SwiftData

/// The complete inventory.
///
/// A native `List` with real sections, search, swipe actions and a context menu.
/// Grouping and sorting live in a toolbar menu rather than on screen, because they are
/// occasional choices and the list itself is what the user came for.
struct PantryView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var allItems: [PantryItem]

    @State private var searchText = ""
    @State private var grouping: PantryGrouping = .category
    @State private var sortOrder: PantrySortOrder = .name
    @State private var categoryFilter: FoodCategory?
    @State private var locationFilter: StorageLocation?
    @State private var showsOnlyNeedingAttention = false

    @State private var presentedSheet: PantrySheet?
    @State private var itemPendingDeletion: PantryItem?
    @State private var selection: PantryItem?

    private var service: InventoryService { InventoryService(context: modelContext) }
    private var windowDays: Int { appEnvironment.preferences.useSoonWindowDays }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    emptyPantry
                } else if visibleItems.isEmpty {
                    noResults
                } else {
                    itemList
                }
            }
            .navigationTitle(Text("Pantry"))
            .searchable(text: $searchText, prompt: Text("Search your pantry"))
            .toolbar { toolbarContent }
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(for: sheet)
            }
            .navigationDestination(for: PantryItem.self) { item in
                PantryItemDetailView(item: item)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .confirmationDialog(
                Text("Remove \(itemPendingDeletion?.name ?? "")?"),
                isPresented: Binding(
                    get: { itemPendingDeletion != nil },
                    set: { if !$0 { itemPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove"), role: .destructive) {
                    if let item = itemPendingDeletion { service.delete(item) }
                    itemPendingDeletion = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { itemPendingDeletion = nil }
            }
            .onChange(of: appEnvironment.pendingRoute) { _, _ in handlePendingRoute() }
            .onAppear { handlePendingRoute() }
        }
    }

    // MARK: - List

    private var itemList: some View {
        List {
            if !filterSummary.isEmpty {
                Section {
                    Button {
                        clearFilters()
                    } label: {
                        Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityHint(Text("Clears the current filter"))
                }
            }

            ForEach(groupedItems, id: \.title) { group in
                Section {
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            PantryItemRow(
                                item: item,
                                useSoonWindowDays: windowDays,
                                onIncrement: { service.adjustQuantity(of: item, by: item.unit.stepIncrement) },
                                onDecrement: { service.adjustQuantity(of: item, by: -item.unit.stepIncrement) }
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                itemPendingDeletion = item
                            } label: {
                                Label(String(localized: "Remove"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation { service.togglePinned(item) }
                            } label: {
                                Label(
                                    item.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                                    systemImage: item.isPinned ? "pin.slash" : "pin"
                                )
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            itemContextMenu(for: item)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if let footer = group.footer {
                        Text(footer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: groupedItems.map(\.title))
    }

    @ViewBuilder
    private func itemContextMenu(for item: PantryItem) -> some View {
        Button {
            presentedSheet = .edit(item)
        } label: {
            Label(String(localized: "Edit"), systemImage: "pencil")
        }
        Button {
            service.toggleOpened(item)
        } label: {
            Label(
                item.isOpened ? String(localized: "Mark as Unopened") : String(localized: "Mark as Opened"),
                systemImage: item.isOpened ? "seal" : "seal.fill"
            )
        }
        Button {
            service.togglePinned(item)
        } label: {
            Label(
                item.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                systemImage: item.isPinned ? "pin.slash" : "pin"
            )
        }
        Divider()
        Button(role: .destructive) {
            itemPendingDeletion = item
        } label: {
            Label(String(localized: "Remove"), systemImage: "trash")
        }
    }

    // MARK: - Empty states

    private var emptyPantry: some View {
        ContentUnavailableView {
            Label(String(localized: "Your Pantry Is Empty"), systemImage: "cabinet")
        } description: {
            Text("Add the food you already have and Pantry can start finding meals for you.")
        } actions: {
            Button {
                presentedSheet = .add
            } label: {
                Text("Add Food")
            }
            .buttonStyle(.borderedProminent)

            Button {
                presentedSheet = .quickAdd
            } label: {
                Text("Add a List")
            }
            .buttonStyle(.borderless)
        }
    }

    private var noResults: some View {
        Group {
            if searchText.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nothing Matches"), systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No items match the filters you've chosen.")
                } actions: {
                    Button(String(localized: "Clear Filters"), action: clearFilters)
                        .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    presentedSheet = .add
                } label: {
                    Label(String(localized: "Add Item"), systemImage: "square.and.pencil")
                }
                Button {
                    presentedSheet = .quickAdd
                } label: {
                    Label(String(localized: "Add a List"), systemImage: "text.badge.plus")
                }
                Button {
                    presentedSheet = .scan
                } label: {
                    Label(String(localized: "Scan Barcode"), systemImage: "barcode.viewfinder")
                }
                Button {
                    presentedSheet = .recognisePhoto
                } label: {
                    Label(String(localized: "Add from Photo"), systemImage: "camera")
                }
            } label: {
                Label(String(localized: "Add"), systemImage: "plus")
            } primaryAction: {
                presentedSheet = .add
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker(String(localized: "Group By"), selection: $grouping) {
                    ForEach(PantryGrouping.allCases) { option in
                        Label(option.name, systemImage: option.symbolName).tag(option)
                    }
                }
                Picker(String(localized: "Sort By"), selection: $sortOrder) {
                    ForEach(PantrySortOrder.allCases) { option in
                        Label(option.name, systemImage: option.symbolName).tag(option)
                    }
                }
                Divider()
                Toggle(isOn: $showsOnlyNeedingAttention) {
                    Label(String(localized: "Only Use Soon"), systemImage: "clock.badge")
                }
                Menu {
                    Picker(String(localized: "Category"), selection: $categoryFilter) {
                        Text("All Categories").tag(FoodCategory?.none)
                        ForEach(FoodCategory.allCases) { category in
                            Label(category.name, systemImage: category.symbolName)
                                .tag(FoodCategory?.some(category))
                        }
                    }
                } label: {
                    Label(String(localized: "Category"), systemImage: "square.grid.2x2")
                }
                Menu {
                    Picker(String(localized: "Location"), selection: $locationFilter) {
                        Text("Anywhere").tag(StorageLocation?.none)
                        ForEach(StorageLocation.allCases) { location in
                            Label(location.name, systemImage: location.symbolName)
                                .tag(StorageLocation?.some(location))
                        }
                    }
                } label: {
                    Label(String(localized: "Location"), systemImage: "refrigerator")
                }
            } label: {
                Label(
                    String(localized: "View Options"),
                    systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: PantrySheet) -> some View {
        switch sheet {
        case .add:
            AddItemView()
        case .edit(let item):
            AddItemView(editing: item)
        case .quickAdd:
            QuickAddView()
        case .scan:
            BarcodeScanSheet()
        case .recognisePhoto:
            PhotoRecognitionSheet()
        }
    }

    // MARK: - Filtering, sorting, grouping

    private var visibleItems: [PantryItem] {
        var items = allItems

        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(query)
                    || item.brand?.localizedCaseInsensitiveContains(query) == true
                    || item.notes?.localizedCaseInsensitiveContains(query) == true
                    || item.category.name.localizedCaseInsensitiveContains(query)
            }
        }
        if let categoryFilter {
            items = items.filter { $0.category == categoryFilter }
        }
        if let locationFilter {
            items = items.filter { $0.location == locationFilter }
        }
        if showsOnlyNeedingAttention {
            items = items.filter {
                ExpirationCalculator.freshness(for: $0.expirationDate, useSoonWindowDays: windowDays).isNoteworthy
            }
        }
        return items.sorted(by: sortOrder.comparator(windowDays: windowDays))
    }

    private var groupedItems: [PantryGroup] {
        let items = visibleItems
        guard !items.isEmpty else { return [] }

        // Pinned items always surface first, whatever the grouping.
        let pinned = items.filter(\.isPinned)
        let rest = items.filter { !$0.isPinned }

        var groups: [PantryGroup] = []
        if !pinned.isEmpty {
            groups.append(PantryGroup(title: String(localized: "Pinned"), items: pinned, footer: nil))
        }
        groups.append(contentsOf: grouping.groups(for: rest, windowDays: windowDays))
        return groups
    }

    private var hasActiveFilters: Bool {
        categoryFilter != nil || locationFilter != nil || showsOnlyNeedingAttention
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let categoryFilter { parts.append(categoryFilter.name) }
        if let locationFilter { parts.append(locationFilter.name) }
        if showsOnlyNeedingAttention { parts.append(String(localized: "Use soon")) }
        guard !parts.isEmpty else { return "" }
        return String(localized: "Filtered: \(parts.joined(separator: " · "))")
    }

    private func clearFilters() {
        withAnimation {
            categoryFilter = nil
            locationFilter = nil
            showsOnlyNeedingAttention = false
        }
    }

    private func handlePendingRoute() {
        guard let route = appEnvironment.takePendingRoute(matching: { route in
            if case .addItem = route { return true }
            if case .quickAdd = route { return true }
            if case .pantryItem = route { return true }
            return false
        }) else { return }

        switch route {
        case .addItem: presentedSheet = .add
        case .quickAdd: presentedSheet = .quickAdd
        case .pantryItem(let id):
            if let item = service.item(withID: id) { presentedSheet = .edit(item) }
        default: break
        }
    }
}

// MARK: - Supporting types

private enum PantrySheet: Identifiable {
    case add
    case edit(PantryItem)
    case quickAdd
    case scan
    case recognisePhoto

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let item): return "edit-\(item.id)"
        case .quickAdd: return "quick-add"
        case .scan: return "scan"
        case .recognisePhoto: return "photo"
        }
    }
}

struct PantryGroup {
    var title: String
    var items: [PantryItem]
    var footer: String?
}

enum PantryGrouping: String, CaseIterable, Identifiable {
    case category
    case location
    case expiry
    case none

    var id: String { rawValue }

    var name: String {
        switch self {
        case .category: return String(localized: "Category")
        case .location: return String(localized: "Location")
        case .expiry: return String(localized: "Use By")
        case .none: return String(localized: "No Grouping")
        }
    }

    var symbolName: String {
        switch self {
        case .category: return "square.grid.2x2"
        case .location: return "refrigerator"
        case .expiry: return "clock"
        case .none: return "list.bullet"
        }
    }

    func groups(for items: [PantryItem], windowDays: Int) -> [PantryGroup] {
        switch self {
        case .none:
            return items.isEmpty ? [] : [PantryGroup(title: String(localized: "All Items"), items: items, footer: nil)]

        case .category:
            return FoodCategory.allCases.compactMap { category in
                let matching = items.filter { $0.category == category }
                guard !matching.isEmpty else { return nil }
                return PantryGroup(title: category.name, items: matching, footer: nil)
            }

        case .location:
            var groups = StorageLocation.allCases.compactMap { location -> PantryGroup? in
                let matching = items.filter { $0.location == location }
                guard !matching.isEmpty else { return nil }
                return PantryGroup(
                    title: location.name,
                    items: matching,
                    footer: matching.count == 1
                        ? String(localized: "1 item")
                        : String(localized: "\(matching.count) items")
                )
            }
            let unassigned = items.filter { $0.location == nil }
            if !unassigned.isEmpty {
                groups.append(PantryGroup(title: String(localized: "No Location"), items: unassigned, footer: nil))
            }
            return groups

        case .expiry:
            var groups: [PantryGroup] = []
            func add(_ title: String, _ matching: [PantryItem]) {
                guard !matching.isEmpty else { return }
                groups.append(PantryGroup(title: title, items: matching, footer: nil))
            }
            add(String(localized: "Date Passed"), items.filter { $0.freshness == .past })
            add(String(localized: "Today"), items.filter { $0.freshness == .today })
            add(String(localized: "Use Soon"), items.filter {
                ExpirationCalculator.freshness(for: $0.expirationDate, useSoonWindowDays: windowDays) == .useSoon
            })
            add(String(localized: "Later"), items.filter {
                ExpirationCalculator.freshness(for: $0.expirationDate, useSoonWindowDays: windowDays) == .fresh
            })
            add(String(localized: "No Date"), items.filter { $0.expirationDate == nil })
            return groups
        }
    }
}

enum PantrySortOrder: String, CaseIterable, Identifiable {
    case name
    case expiry
    case recentlyAdded
    case quantity

    var id: String { rawValue }

    var name: String {
        switch self {
        case .name: return String(localized: "Name")
        case .expiry: return String(localized: "Use By")
        case .recentlyAdded: return String(localized: "Recently Added")
        case .quantity: return String(localized: "Quantity")
        }
    }

    var symbolName: String {
        switch self {
        case .name: return "textformat"
        case .expiry: return "clock"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .quantity: return "number"
        }
    }

    func comparator(windowDays: Int) -> (PantryItem, PantryItem) -> Bool {
        switch self {
        case .name:
            return { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .expiry:
            return {
                ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture)
            }
        case .recentlyAdded:
            return { $0.dateAdded > $1.dateAdded }
        case .quantity:
            return { $0.quantity < $1.quantity }
        }
    }
}

#Preview {
    PantryView()
        .environment(AppEnvironment())
        .modelContainer(SampleData.previewContainer())
}
