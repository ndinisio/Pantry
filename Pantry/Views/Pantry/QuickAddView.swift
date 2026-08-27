import SwiftUI
import SwiftData

/// Adding several things at once.
///
/// Handles both a plain list, one item per line, and a sentence — "I bought 2 litres of
/// milk, a pack of chicken breasts and six eggs". Parsing happens locally as you type,
/// and every parsed row is shown and editable before anything is saved, so the user is
/// never surprised by what lands in their pantry.
struct QuickAddView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @State private var parsed: [NaturalLanguageItemParser.ParsedItem] = []
    @State private var location: StorageLocation?
    @FocusState private var isEditorFocused: Bool

    private let quickAddTip = QuickAddTip()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "milk\nsix eggs\n500g chicken"),
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                    .focused($isEditorFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(String(localized: "Items to add"))
                    .accessibilityHint(String(localized: "One item per line, or a sentence"))
                } header: {
                    Text("What did you get?")
                } footer: {
                    Text("One per line, or write it as a sentence. Pantry works out the quantities.")
                }

                if !parsed.isEmpty {
                    Section {
                        ForEach($parsed) { $item in
                            ParsedItemRow(item: $item)
                        }
                        .onDelete { offsets in
                            parsed.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text(parsed.count == 1 ? "1 Item" : "\(parsed.count) Items")
                    } footer: {
                        Text("Swipe to remove anything you didn't mean. Tap to change a quantity.")
                    }

                    Section {
                        Picker(String(localized: "Put Away In"), selection: $location) {
                            Text("Decide later").tag(StorageLocation?.none)
                            ForEach(StorageLocation.allCases) { option in
                                Label(option.name, systemImage: option.symbolName)
                                    .tag(StorageLocation?.some(option))
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("Add a List"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add \(parsed.count)"), action: save)
                        .disabled(parsed.isEmpty)
                }
            }
            .onChange(of: text) { _, newValue in
                withAnimation(.default) {
                    parsed = parse(newValue)
                }
            }
            .onAppear { isEditorFocused = true }
        }
    }

    /// A line break means "next item"; a sentence with commas is parsed as prose.
    private func parse(_ input: String) -> [NaturalLanguageItemParser.ParsedItem] {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if input.contains(where: \.isNewline) {
            return NaturalLanguageItemParser.parseLines(input)
        }
        return NaturalLanguageItemParser.parse(input)
    }

    private func save() {
        let items = parsed.map { parsedItem -> PantryItem in
            let item = parsedItem.makePantryItem()
            item.location = location
            return item
        }
        InventoryService(context: modelContext).add(items)
        quickAddTip.invalidate(reason: .actionPerformed)
        dismiss()
    }
}

/// One parsed row, editable in place before it is committed.
private struct ParsedItemRow: View {
    @Binding var item: NaturalLanguageItemParser.ParsedItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(item.category.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            InlineQuantityStepper(
                quantity: item.quantity,
                unit: item.unit,
                onDecrement: { item.quantity = QuantityFormatter.normalise(item.quantity - item.unit.stepIncrement, unit: item.unit) },
                onIncrement: { item.quantity = QuantityFormatter.normalise(item.quantity + item.unit.stepIncrement, unit: item.unit) }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(QuantityFormatter.accessibleString(quantity: item.quantity, unit: item.unit))")
    }
}

#Preview {
    QuickAddView()
        .modelContainer(SampleData.previewContainer())
}
