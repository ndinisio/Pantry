import SwiftUI
import SwiftData

/// Adding something to the shopping list by hand.
///
/// Same shape as adding to the pantry: name and quantity are enough, and the category
/// is inferred as you type. Priority defaults to Needed because that is what someone
/// typing an item by hand almost always means.
struct AddShoppingItemView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var quantity: Double = 1
    @State private var unit: MeasurementUnit = .piece
    @State private var priority: ShoppingPriority = .needed
    @State private var notes = ""
    @State private var didChooseUnitManually = false
    @FocusState private var isNameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)

                    QuantityStepper(quantity: $quantity, unit: unit, title: String(localized: "Quantity"))

                    Picker(String(localized: "Unit"), selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                }

                Section {
                    Picker(String(localized: "Priority"), selection: $priority) {
                        ForEach(ShoppingPriority.allCases) { option in
                            Label(option.name, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Why")
                } footer: {
                    Text(priority.footnote)
                }

                Section(String(localized: "Notes")) {
                    TextField(String(localized: "Optional"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(Text("Add to List"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add"), action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear { isNameFocused = true }
            .onChange(of: name) { _, newValue in
                guard !didChooseUnitManually else { return }
                unit = CategoryGuesser.unit(for: newValue)
            }
            .onChange(of: unit) { oldValue, newValue in
                if oldValue != newValue, CategoryGuesser.unit(for: name) != newValue {
                    didChooseUnitManually = true
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ShoppingItem(
            name: trimmed,
            category: CategoryGuesser.category(for: trimmed),
            quantity: QuantityFormatter.normalise(quantity, unit: unit),
            unit: unit,
            priority: priority,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddShoppingItemView()
        .modelContainer(SampleData.previewContainer())
}
