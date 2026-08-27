import SwiftUI
import SwiftData

/// Cooking preferences.
///
/// Everything here has one job: make suggestions better. Nothing is required, and the
/// screen is a plain `Form` rather than a designed profile, because that is what a
/// person expects settings to look like on iOS.
struct PreferencesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var preferences: UserPreferences?

    var body: some View {
        Form {
            if let preferences {
                content(for: preferences)
            }
        }
        .navigationTitle(Text("Cooking Preferences"))
        .onAppear {
            if preferences == nil {
                preferences = PantryModelContainer.preferences(in: modelContext)
            }
        }
        // Bindings write straight through to the model, so the snapshot the services
        // read is refreshed once on the way out rather than on every keystroke.
        .onDisappear {
            if let preferences { save(preferences) }
        }
    }

    @ViewBuilder
    private func content(for preferences: UserPreferences) -> some View {
        @Bindable var preferences = preferences

        Section {
            Picker(String(localized: "Diet"), selection: $preferences.dietaryStyle) {
                ForEach(DietaryStyle.allCases) { style in
                    Text(style.name).tag(style)
                }
            }
            NavigationLink {
                EditableListView(
                    title: String(localized: "Allergies & Intolerances"),
                    footer: String(localized: "Pantry will never suggest a recipe containing these."),
                    placeholder: String(localized: "Peanuts"),
                    values: $preferences.allergies
                )
            } label: {
                LabeledContent(String(localized: "Allergies")) {
                    Text(summary(preferences.allergies))
                }
            }
            NavigationLink {
                EditableListView(
                    title: String(localized: "Foods You Dislike"),
                    footer: String(localized: "These are avoided in suggestions."),
                    placeholder: String(localized: "Olives"),
                    values: $preferences.dislikedFoods
                )
            } label: {
                LabeledContent(String(localized: "Dislikes")) {
                    Text(summary(preferences.dislikedFoods))
                }
            }
            NavigationLink {
                EditableListView(
                    title: String(localized: "Favourite Cuisines"),
                    footer: String(localized: "Recipes from these are nudged up the list."),
                    placeholder: String(localized: "Italian"),
                    values: $preferences.favouriteCuisines
                )
            } label: {
                LabeledContent(String(localized: "Cuisines")) {
                    Text(summary(preferences.favouriteCuisines))
                }
            }
        } header: {
            Text("Food")
        } footer: {
            Text("Allergies are treated as a hard rule. Dislikes are a strong preference.")
        }

        Section {
            Stepper(value: $preferences.defaultServings, in: 1...12) {
                LabeledContent(String(localized: "Usual Servings")) {
                    Text("\(preferences.defaultServings)").monospacedDigit()
                }
            }
            Picker(String(localized: "Confidence in the Kitchen"), selection: $preferences.skillLevel) {
                ForEach(RecipeDifficulty.allCases) { level in
                    Text(level.name).tag(level)
                }
            }
            Picker(String(localized: "Usual Time"), selection: $preferences.maxCookingTimeMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("45 min").tag(45)
                Text("1 hour").tag(60)
                Text("No limit").tag(600)
            }
            Picker(String(localized: "Budget"), selection: $preferences.budgetPreference) {
                ForEach(BudgetPreference.allCases) { option in
                    Text(option.name).tag(option)
                }
            }
        } header: {
            Text("Cooking")
        }

        Section {
            ForEach(CookingEquipment.allCases) { equipment in
                Toggle(isOn: binding(for: equipment, in: preferences)) {
                    Label(equipment.name, systemImage: equipment.symbolName)
                }
            }
        } header: {
            Text("Your Kitchen")
        } footer: {
            Text("Recipes that need equipment you don't have are left out.")
        }

        Section {
            Picker(String(localized: "Count as \"Use Soon\""), selection: $preferences.useSoonWindowDays) {
                Text("1 day").tag(1)
                Text("2 days").tag(2)
                Text("3 days").tag(3)
                Text("5 days").tag(5)
                Text("A week").tag(7)
            }
        } header: {
            Text("Dates")
        } footer: {
            Text("How far ahead something counts as needing to be used.")
        }
    }

    private func binding(for equipment: CookingEquipment, in preferences: UserPreferences) -> Binding<Bool> {
        Binding(
            get: { preferences.equipment.contains(equipment.rawValue) },
            set: { isOn in
                if isOn {
                    if !preferences.equipment.contains(equipment.rawValue) {
                        preferences.equipment.append(equipment.rawValue)
                    }
                } else {
                    preferences.equipment.removeAll { $0 == equipment.rawValue }
                }
                save(preferences)
            }
        )
    }

    private func summary(_ values: [String]) -> String {
        values.isEmpty ? String(localized: "None") : values.joined(separator: ", ")
    }

    private func save(_ preferences: UserPreferences) {
        preferences.lastUpdated = .now
        try? modelContext.save()
        appEnvironment.preferences = PreferenceSnapshot(preferences)
    }
}

/// A reusable editable list of short strings — allergies, dislikes, cuisines.
struct EditableListView: View {
    let title: String
    let footer: String
    let placeholder: String
    @Binding var values: [String]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var newValue = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(values, id: \.self) { value in
                    Text(value)
                }
                .onDelete { offsets in
                    values.remove(atOffsets: offsets)
                    persist()
                }

                HStack {
                    TextField(placeholder, text: $newValue)
                        .focused($isFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(String(localized: "Add"))
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(title)
        .toolbar { EditButton() }
    }

    private func add() {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !values.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newValue = ""
            return
        }
        values.append(trimmed)
        newValue = ""
        isFieldFocused = true
        persist()
    }

    private func persist() {
        let record = PantryModelContainer.preferences(in: modelContext)
        record.lastUpdated = .now
        try? modelContext.save()
        appEnvironment.preferences = PreferenceSnapshot(record)
    }
}

#Preview {
    NavigationStack {
        PreferencesView()
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
