import SwiftUI
import SwiftData

/// Sample content and housekeeping.
///
/// Sample data is opt-in and removable in one action: every sample item carries a
/// marker, so removing it never touches anything the user added themselves.
struct DataSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query private var items: [PantryItem]
    @Query private var recipes: [Recipe]
    @Query private var shoppingItems: [ShoppingItem]

    @State private var hasSampleData = false
    @State private var isConfirmingRemoveSamples = false
    @State private var isConfirmingClearAll = false

    private var generatedUnsaved: [Recipe] {
        recipes.filter { $0.origin == .generated && !$0.isSaved }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Pantry items")) {
                    Text("\(items.count)").monospacedDigit()
                }
                LabeledContent(String(localized: "Recipes")) {
                    Text("\(recipes.count)").monospacedDigit()
                }
                LabeledContent(String(localized: "Shopping items")) {
                    Text("\(shoppingItems.count)").monospacedDigit()
                }
            } header: {
                Text("Stored on This Device")
            } footer: {
                Text("Everything Pantry knows is stored on your device. Nothing is uploaded unless you ask for a suggestion from a provider that isn't on-device.")
            }

            Section {
                if hasSampleData {
                    Button(String(localized: "Remove Sample Content"), role: .destructive) {
                        isConfirmingRemoveSamples = true
                    }
                } else {
                    Button(String(localized: "Add Sample Content")) {
                        SampleData.populate(context: modelContext)
                        refresh()
                    }
                }
            } header: {
                Text("Sample Content")
            } footer: {
                Text("A realistic starter pantry for trying the app out. Removing it only removes the sample items — anything you added stays.")
            }

            Section {
                Button(String(localized: "Reinstall Recipe Library")) {
                    RecipeLibrary.installIfNeeded(context: modelContext)
                }
                if !generatedUnsaved.isEmpty {
                    Button(String(localized: "Clear \(generatedUnsaved.count) Unsaved Suggestions"), role: .destructive) {
                        for recipe in generatedUnsaved { modelContext.delete(recipe) }
                        try? modelContext.save()
                    }
                }
            } header: {
                Text("Recipes")
            } footer: {
                Text("Generated recipes you haven't saved are kept only until you clear them.")
            }

            Section {
                Button(String(localized: "Delete Everything"), role: .destructive) {
                    isConfirmingClearAll = true
                }
            } footer: {
                Text("Removes your whole pantry, shopping list, plan and saved recipes. This can't be undone.")
            }
        }
        .navigationTitle(Text("Data & Sample Content"))
        .onAppear(perform: refresh)
        .confirmationDialog(
            Text("Remove sample content?"),
            isPresented: $isConfirmingRemoveSamples,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                SampleData.remove(context: modelContext)
                refresh()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            Text("Delete everything in Pantry?"),
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Everything"), role: .destructive, action: clearAll)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Your pantry, shopping list, meal plan and saved recipes will be removed from this device.")
        }
    }

    private func refresh() {
        hasSampleData = SampleData.isPresent(in: modelContext)
    }

    private func clearAll() {
        for item in items { modelContext.delete(item) }
        for item in shoppingItems { modelContext.delete(item) }
        for recipe in recipes { modelContext.delete(recipe) }
        for entry in (try? modelContext.fetch(FetchDescriptor<MealPlanEntry>())) ?? [] {
            modelContext.delete(entry)
        }
        for session in (try? modelContext.fetch(FetchDescriptor<CookingSession>())) ?? [] {
            modelContext.delete(session)
        }
        try? modelContext.save()
        RecipeLibrary.installIfNeeded(context: modelContext)
        refresh()
    }
}

/// What the app is, and what it does with your data.
struct AboutView: View {
    private var version: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        List {
            Section {
                Text("Know what you have. Know what to cook. Know what to buy.")
                    .font(.headline)
                Text("Pantry keeps track of the food in your kitchen and uses it to suggest meals, flag what needs using and work out what's worth buying.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label(String(localized: "Your pantry, recipes and lists live on this device."), systemImage: "iphone")
                Label(String(localized: "Suggestions run on device when Apple's model is available."), systemImage: "lock")
                Label(String(localized: "When a network provider is used, only a short summary of your kitchen is sent — never your whole inventory, photos or dates."), systemImage: "arrow.up.forward.app")
                Label(String(localized: "Photo recognition happens entirely on device."), systemImage: "camera")
            } header: {
                Text("Privacy")
            }

            Section {
                Text("Expiry dates in Pantry are reminders to use something up, not statements about food safety. Nutrition figures generated by a model are estimates, not nutritional advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("A Note on Dates and Nutrition")
            }

            Section {
                LabeledContent(String(localized: "Version"), value: version)
            }
        }
        .navigationTitle(Text("About Pantry"))
    }
}

#Preview {
    NavigationStack {
        DataSettingsView()
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
