import SwiftUI
import SwiftData

/// "I don't have butter."
///
/// Anything the recipe itself already lists as a substitution is shown instantly, with
/// no network. Asking a model is an extra step, and its answers are marked as such.
struct SubstitutionSheet: View {

    let ingredient: RecipeIngredient
    let recipeTitle: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]

    @State private var state: AIState<AIResponses.SubstitutionList> = .idle
    @State private var task: Task<Void, Never>?

    private var index: InventoryIndex {
        InventoryIndex(items: items, useSoonWindowDays: appEnvironment.preferences.useSoonWindowDays)
    }

    var body: some View {
        NavigationStack {
            List {
                if !ingredient.substitutions.isEmpty {
                    Section {
                        ForEach(ingredient.substitutions, id: \.self) { name in
                            SubstitutionRow(name: name, note: nil, isOwned: index.contains(name))
                        }
                    } header: {
                        Text("From This Recipe")
                    }
                }

                Section {
                    switch state {
                    case .idle:
                        Button {
                            findMore()
                        } label: {
                            Label(String(localized: "Suggest Substitutes"), systemImage: "sparkles")
                        }
                    case .loading:
                        AIProgressView(
                            message: String(localized: "Looking for something you already have…"),
                            cancel: { task?.cancel(); state = .idle }
                        )
                    case .loaded(let result):
                        ForEach(result.value.substitutions) { substitution in
                            SubstitutionRow(
                                name: substitution.name,
                                note: substitution.howToUse,
                                isOwned: index.contains(substitution.name)
                            )
                        }
                    case .failed(let error):
                        AIErrorView(error: error, retry: findMore)
                    }
                } header: {
                    Text("Other Ideas")
                } footer: {
                    if case .loaded(let result) = state {
                        AIProvenanceFooter(
                            providerName: result.providerName,
                            wasOnDevice: result.wasOnDevice,
                            isSample: result.isSample
                        )
                    } else if ingredient.substitutions.isEmpty, case .idle = state {
                        Text("This recipe doesn't list any swaps for \(ingredient.name).")
                    }
                }
            }
            .navigationTitle(Text("No \(ingredient.name)?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onDisappear { task?.cancel() }
        }
        .presentationDetents([.medium, .large])
    }

    private func findMore() {
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let result = try await appEnvironment.aiService.substitutions(
                    for: ingredient.name,
                    recipeTitle: recipeTitle,
                    inventory: items,
                    preferences: appEnvironment.preferences
                )
                guard !Task.isCancelled else { return }
                state = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                state = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }
}

/// One suggested swap. "In your pantry" is the most useful thing this row can say, so
/// it is the thing it says first.
private struct SubstitutionRow: View {
    var name: String
    var note: String?
    var isOwned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.body)
                if isOwned {
                    Label(String(localized: "In your pantry"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .labelStyle(.titleAndIcon)
                }
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
