import SwiftUI
import SwiftData
import UIKit

/// Cooking mode.
///
/// One step at a time, in large type, with the screen kept awake while it is open —
/// because the phone is on the counter and your hands are wet. It is presented full
/// screen because that is the one place in this app where total focus is the point.
struct CookingModeView: View {

    let recipe: Recipe
    let servings: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stepIndex = 0
    @State private var isConfirmingExit = false
    @State private var isShowingIngredients = false
    @State private var isFinishing = false

    private var steps: [String] { recipe.steps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var scale: Double { recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(stepIndex + 1), total: Double(max(1, steps.count)))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Step \(stepIndex + 1) of \(steps.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(currentStep)
                            .font(.title2)
                            .fontWeight(.regular)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Step \(stepIndex + 1) of \(steps.count). \(currentStep)"))

                controls
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) {
                        if stepIndex > 0 && !isLastStep {
                            isConfirmingExit = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingIngredients = true
                    } label: {
                        Label(String(localized: "Ingredients"), systemImage: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $isShowingIngredients) {
                ingredientsSheet
            }
            .sheet(isPresented: $isFinishing) {
                FinishCookingView(recipe: recipe, servings: servings) {
                    dismiss()
                }
            }
            .confirmationDialog(
                Text("Stop cooking?"),
                isPresented: $isConfirmingExit,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Stop"), role: .destructive) { dismiss() }
                Button(String(localized: "Keep Cooking"), role: .cancel) {}
            } message: {
                Text("You're on step \(stepIndex + 1) of \(steps.count).")
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var currentStep: String {
        guard steps.indices.contains(stepIndex) else { return "" }
        return steps[stepIndex]
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                advance(by: -1)
            } label: {
                Label(String(localized: "Previous"), systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(stepIndex == 0)

            Button {
                if isLastStep {
                    isFinishing = true
                } else {
                    advance(by: 1)
                }
            } label: {
                Label(
                    isLastStep ? String(localized: "Finish") : String(localized: "Next"),
                    systemImage: isLastStep ? "checkmark" : "chevron.right"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var ingredientsSheet: some View {
        NavigationStack {
            List {
                ForEach(recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }) { ingredient in
                    Text(ingredient.displayDescription(scaledBy: scale))
                }
            }
            .navigationTitle(Text("Ingredients"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { isShowingIngredients = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func advance(by delta: Int) {
        let target = min(max(0, stepIndex + delta), max(0, steps.count - 1))
        // Reduce Motion turns the step change into a plain swap; the information is in
        // the text, never in the transition.
        if reduceMotion {
            stepIndex = target
        } else {
            withAnimation(.snappy(duration: 0.25)) { stepIndex = target }
        }
    }
}

/// What happens after the last step: record the cook, optionally update the pantry,
/// and offer something to do with what is left over.
struct FinishCookingView: View {

    let recipe: Recipe
    let servings: Int
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]

    @State private var updatesInventory = true
    @State private var leftoverText = ""
    @State private var leftoverState: AIState<AIResponses.LeftoverIdeas> = .idle
    @State private var leftoverTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Take Ingredients Out of My Pantry"), isOn: $updatesInventory)
                } footer: {
                    Text("Pantry will subtract roughly what this recipe used. You can always adjust quantities afterwards.")
                }

                Section {
                    TextField(String(localized: "Half an onion, some cooked chicken…"), text: $leftoverText, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        findLeftoverIdeas()
                    } label: {
                        Label(String(localized: "Ideas for Leftovers"), systemImage: "sparkles")
                    }
                    .disabled(leftoverText.trimmingCharacters(in: .whitespaces).isEmpty || leftoverState.isLoading)
                } header: {
                    Text("Anything Left Over?")
                } footer: {
                    Text("Optional. Skip it and finish.")
                }

                switch leftoverState {
                case .idle:
                    EmptyView()
                case .loading:
                    Section {
                        AIProgressView(
                            message: String(localized: "Thinking about your leftovers…"),
                            cancel: { leftoverTask?.cancel(); leftoverState = .idle }
                        )
                    }
                case .loaded(let result):
                    Section {
                        ForEach(result.value.ideas) { idea in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title).font(.headline)
                                Text(idea.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } footer: {
                        AIProvenanceFooter(
                            providerName: result.providerName,
                            wasOnDevice: result.wasOnDevice,
                            isSample: result.isSample
                        )
                    }
                case .failed(let error):
                    Section {
                        AIErrorView(error: error, retry: findLeftoverIdeas)
                    }
                }
            }
            .navigationTitle(Text("Nicely Done"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done"), action: finish)
                }
            }
            .onDisappear { leftoverTask?.cancel() }
        }
    }

    private func finish() {
        let service = InventoryService(context: modelContext)
        let session = service.markCooked(recipe, servings: servings, consumeInventory: updatesInventory)
        if !leftoverText.trimmingCharacters(in: .whitespaces).isEmpty {
            session.leftoverNote = leftoverText
            service.save()
        }
        dismiss()
        onDone()
    }

    private func findLeftoverIdeas() {
        leftoverTask?.cancel()
        leftoverState = .loading
        leftoverTask = Task {
            do {
                let result = try await appEnvironment.aiService.leftoverIdeas(
                    leftovers: leftoverText,
                    inventory: items,
                    preferences: appEnvironment.preferences
                )
                guard !Task.isCancelled else { return }
                leftoverState = .loaded(result)
            } catch let error as AIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                leftoverState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                leftoverState = .failed(.server(status: 0, message: error.localizedDescription))
            }
        }
    }
}
