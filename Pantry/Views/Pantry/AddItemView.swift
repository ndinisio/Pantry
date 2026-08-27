import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Adding or editing one item.
///
/// The whole screen is arranged around one idea: name, quantity, done. Everything else
/// is below the fold and optional, and the category and unit are guessed from the name
/// as it is typed so the common case needs no pickers at all.
struct AddItemView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Non-nil when editing an existing item.
    private let editingItem: PantryItem?

    @State private var name: String
    @State private var quantity: Double
    @State private var unit: MeasurementUnit
    @State private var category: FoodCategory
    @State private var location: StorageLocation?
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var isOpened: Bool
    @State private var isPinned: Bool
    @State private var brand: String
    @State private var notes: String
    @State private var barcode: String
    @State private var photoData: Data?
    @State private var photoSelection: PhotosPickerItem?
    @State private var showsMoreDetails: Bool

    /// True once the user picks a category by hand, so guessing stops overriding them.
    @State private var didChooseCategoryManually = false
    @State private var didChooseUnitManually = false

    @FocusState private var isNameFocused: Bool

    init(editing item: PantryItem? = nil, initialName: String = "") {
        editingItem = item
        _name = State(initialValue: item?.name ?? initialName)
        _quantity = State(initialValue: item?.quantity ?? 1)
        _unit = State(initialValue: item?.unit ?? CategoryGuesser.unit(for: initialName))
        _category = State(initialValue: item?.category ?? CategoryGuesser.category(for: initialName))
        _location = State(initialValue: item?.location)
        _hasExpiration = State(initialValue: item?.expirationDate != nil)
        _expirationDate = State(
            initialValue: item?.expirationDate
                ?? ExpirationCalculator.suggestedExpiration(for: item?.category ?? .other)
                ?? Date.now.addingTimeInterval(7 * 86_400)
        )
        _isOpened = State(initialValue: item?.isOpened ?? false)
        _isPinned = State(initialValue: item?.isPinned ?? false)
        _brand = State(initialValue: item?.brand ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _barcode = State(initialValue: item?.barcode ?? "")
        _photoData = State(initialValue: item?.photoData)
        _showsMoreDetails = State(initialValue: item != nil)
    }

    private var isEditing: Bool { editingItem != nil }

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
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .onSubmit(save)

                    QuantityStepper(quantity: $quantity, unit: unit, title: String(localized: "Quantity"))

                    Picker(String(localized: "Unit"), selection: $unit) {
                        unitOptions
                    }
                } footer: {
                    if !isEditing {
                        Text("Name and quantity are all you need. Everything else is optional.")
                    }
                }

                Section {
                    Picker(String(localized: "Category"), selection: $category) {
                        ForEach(FoodCategory.allCases) { option in
                            Label(option.name, systemImage: option.symbolName).tag(option)
                        }
                    }

                    Picker(String(localized: "Location"), selection: $location) {
                        Text("None").tag(StorageLocation?.none)
                        ForEach(StorageLocation.allCases) { option in
                            Label(option.name, systemImage: option.symbolName)
                                .tag(StorageLocation?.some(option))
                        }
                    }

                    Toggle(String(localized: "Use By Date"), isOn: $hasExpiration.animation())
                    if hasExpiration {
                        DatePicker(
                            String(localized: "Use By"),
                            selection: $expirationDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    DisclosureGroup(String(localized: "More Details"), isExpanded: $showsMoreDetails) {
                        Toggle(String(localized: "Opened"), isOn: $isOpened)
                        Toggle(String(localized: "Pinned"), isOn: $isPinned)

                        TextField(String(localized: "Brand"), text: $brand)
                            .textInputAutocapitalization(.words)

                        TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                            .lineLimit(1...4)

                        LabeledContent(String(localized: "Barcode")) {
                            TextField(String(localized: "Optional"), text: $barcode)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                        }

                        photoRow
                    }
                }
            }
            .navigationTitle(isEditing ? Text("Edit Item") : Text("Add Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "Save") : String(localized: "Add"), action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if !isEditing { isNameFocused = true }
            }
            .onChange(of: name) { _, newValue in
                guard !isEditing else { return }
                if !didChooseCategoryManually {
                    category = CategoryGuesser.category(for: newValue)
                }
                if !didChooseUnitManually {
                    unit = CategoryGuesser.unit(for: newValue)
                }
            }
            .onChange(of: category) { oldValue, newValue in
                if oldValue != newValue, CategoryGuesser.category(for: name) != newValue {
                    didChooseCategoryManually = true
                }
                // Keep the suggested date in step with the category until it is edited.
                if hasExpiration, !isEditing,
                   let suggested = ExpirationCalculator.suggestedExpiration(for: newValue) {
                    expirationDate = suggested
                }
            }
            .onChange(of: unit) { oldValue, newValue in
                if oldValue != newValue, CategoryGuesser.unit(for: name) != newValue {
                    didChooseUnitManually = true
                }
            }
            .task(id: photoSelection) {
                guard let photoSelection else { return }
                photoData = try? await photoSelection.loadTransferable(type: Data.self)
            }
        }
    }

    @ViewBuilder
    private var unitOptions: some View {
        Section(String(localized: "Count")) {
            ForEach(MeasurementUnit.countUnits) { option in
                Text(option.name).tag(option)
            }
        }
        Section(String(localized: "Weight")) {
            ForEach(MeasurementUnit.massUnits) { option in
                Text(option.name).tag(option)
            }
        }
        Section(String(localized: "Volume")) {
            ForEach(MeasurementUnit.volumeUnits) { option in
                Text(option.name).tag(option)
            }
        }
    }

    @ViewBuilder
    private var photoRow: some View {
        if let photoData, let image = UIImage(data: photoData) {
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel(String(localized: "Item photo"))
                Spacer()
                Button(String(localized: "Remove"), role: .destructive) {
                    self.photoData = nil
                    self.photoSelection = nil
                }
                .buttonStyle(.borderless)
            }
        } else {
            PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                Label(String(localized: "Add Photo"), systemImage: "photo")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let service = InventoryService(context: modelContext)

        if let editingItem {
            editingItem.name = trimmedName
            editingItem.quantity = QuantityFormatter.normalise(quantity, unit: unit)
            editingItem.unit = unit
            editingItem.category = category
            editingItem.location = location
            editingItem.expirationDate = hasExpiration ? expirationDate : nil
            editingItem.isOpened = isOpened
            editingItem.openedDate = isOpened ? (editingItem.openedDate ?? .now) : nil
            editingItem.isPinned = isPinned
            editingItem.brand = brand.isEmpty ? nil : brand
            editingItem.notes = notes.isEmpty ? nil : notes
            editingItem.barcode = barcode.isEmpty ? nil : barcode
            editingItem.photoData = photoData
            editingItem.touch()
            service.save()
        } else {
            let item = PantryItem(
                name: trimmedName,
                category: category,
                quantity: QuantityFormatter.normalise(quantity, unit: unit),
                unit: unit,
                expirationDate: hasExpiration ? expirationDate : nil,
                location: location,
                brand: brand.isEmpty ? nil : brand,
                notes: notes.isEmpty ? nil : notes,
                isPinned: isPinned,
                isOpened: isOpened,
                barcode: barcode.isEmpty ? nil : barcode,
                photoData: photoData
            )
            service.add(item)
        }
        dismiss()
    }
}

#Preview("Add") {
    AddItemView()
        .modelContainer(SampleData.previewContainer())
}
