import SwiftUI
import SwiftData
import UIKit

/// One item, and — more usefully — what to cook with it.
///
/// The detail screen answers the question the user actually has when they tap an item
/// that is about to go: "so what do I do with this?" Recipe suggestions come from the
/// local matcher first, so the answer appears immediately and without a network.
struct PantryItemDetailView: View {

    @Bindable var item: PantryItem

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @Query private var allItems: [PantryItem]
    @Query private var allRecipes: [Recipe]

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isPresentingIdeas = false

    private var service: InventoryService { InventoryService(context: modelContext) }
    private var windowDays: Int { appEnvironment.preferences.useSoonWindowDays }

    private var suggestions: [RecipeMatch] {
        RecipeMatcher.recipes(using: item, from: allRecipes.browsable, inventory: allItems, limit: 4)
    }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Quantity")) {
                    InlineQuantityStepper(
                        quantity: item.quantity,
                        unit: item.unit,
                        onDecrement: { service.adjustQuantity(of: item, by: -item.unit.stepIncrement) },
                        onIncrement: { service.adjustQuantity(of: item, by: item.unit.stepIncrement) }
                    )
                }

                LabeledContent(String(localized: "Category")) {
                    Label(item.category.name, systemImage: item.category.symbolName)
                        .labelStyle(.titleAndIcon)
                }

                if let location = item.location {
                    LabeledContent(String(localized: "Location")) {
                        Label(location.name, systemImage: location.symbolName)
                            .labelStyle(.titleAndIcon)
                    }
                }

                if let status = ExpirationCalculator.statusDescription(for: item.expirationDate, useSoonWindowDays: windowDays) {
                    LabeledContent(String(localized: "Use By")) {
                        Text(status)
                            .foregroundStyle(item.freshness.isNoteworthy ? .primary : .secondary)
                    }
                }

                Toggle(String(localized: "Opened"), isOn: Binding(
                    get: { item.isOpened },
                    set: { _ in service.toggleOpened(item) }
                ))
            } header: {
                if let photoData = item.photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .padding(.bottom, 8)
                        .accessibilityLabel(String(localized: "Photo of \(item.name)"))
                }
            } footer: {
                if item.freshness == .past {
                    Text("Dates are a guide, not a rule. Trust how it looks and smells.")
                }
            }

            if let brand = item.brand, !brand.isEmpty {
                Section(String(localized: "Brand")) { Text(brand) }
            }

            if let notes = item.notes, !notes.isEmpty {
                Section(String(localized: "Notes")) { Text(notes) }
            }

            if let nutrition = item.nutrition, !nutrition.isEmpty {
                NutritionSection(nutrition: nutrition, title: String(localized: "Nutrition"))
            }

            Section {
                if suggestions.isEmpty {
                    Text("No recipes in your library use this yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions) { match in
                        NavigationLink(value: match.recipe) {
                            RecipeRow(match: match)
                        }
                    }
                }
                Button {
                    isPresentingIdeas = true
                } label: {
                    Label(String(localized: "Find More Ideas"), systemImage: "sparkles")
                }
            } header: {
                Text("Good Ways to Use It")
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label(String(localized: "Remove from Pantry"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    service.togglePinned(item)
                } label: {
                    Label(
                        item.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                        systemImage: item.isPinned ? "pin.fill" : "pin"
                    )
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Edit")) { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            AddItemView(editing: item)
        }
        .sheet(isPresented: $isPresentingIdeas) {
            NavigationStack {
                WhatCanIMakeView(preselectedItemName: item.name)
            }
        }
        .confirmationDialog(
            Text("Remove \(item.name)?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                service.delete(item)
                dismiss()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack {
        PantryItemDetailView(
            item: PantryItem(name: "Greek Yogurt", category: .dairy, quantity: 500, unit: .gram,
                             expirationDate: .now.addingTimeInterval(86_400), location: .fridge, isOpened: true)
        )
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
