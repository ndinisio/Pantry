import Foundation
import OSLog

/// A validated answer plus where it came from.
struct AIResult<Value> {
    var value: Value
    var providerName: String
    var wasOnDevice: Bool
    /// True when the answer came from the sample provider and must be labelled as such.
    var isSample: Bool
}

/// The single door between Pantry and any model.
///
/// Responsibilities, all in one place so no view ever has to think about them:
/// choose an available provider, ask, decode, validate, retry once with a stricter
/// prompt if the shape was wrong, then fall through to the next provider. If every
/// provider fails it throws. It never returns invented content, and it never hides a
/// failure behind a plausible-looking answer.
final class AIService {

    private let providers: [any AIProvider]
    private let contextBuilder: AIContextBuilder
    private let sampleProviderName: String?

    init(providers: [any AIProvider], contextBuilder: AIContextBuilder = AIContextBuilder(), sampleProviderName: String? = nil) {
        self.providers = providers
        self.contextBuilder = contextBuilder
        self.sampleProviderName = sampleProviderName
    }

    /// Provider order is deliberate: on-device first (private, free, works offline),
    /// then a proxy the user controls, then Groq directly. The sample provider is only
    /// included when the developer has explicitly switched it on.
    static func makeDefault(includeSampleProvider: Bool = false) -> AIService {
        var providers: [any AIProvider] = [
            FoundationModelsProvider(),
            ProxyProvider(),
            GroqProvider()
        ]
        let sample = DemoProvider()
        if includeSampleProvider {
            providers.append(sample)
        }
        return AIService(providers: providers, sampleProviderName: includeSampleProvider ? sample.name : nil)
    }

    /// Providers that could serve a request right now, in priority order.
    func availableProviders() async -> [String] {
        var names: [String] = []
        for provider in providers where await provider.isAvailable() {
            names.append(provider.name)
        }
        return names
    }

    var isConfigured: Bool {
        get async { await availableProviders().isEmpty == false }
    }

    // MARK: - Features

    func suggestRecipes(
        inventory: [PantryItem],
        preferences: PreferenceSnapshot,
        query: RecipeQuery,
        count: Int = 3
    ) async throws -> AIResult<[AIResponses.RecipeSuggestion]> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        let request = AIPrompts.recipeSuggestions(
            context: context,
            count: count,
            query: query,
            servings: preferences.defaultServings
        )
        let result = try await run(request, expecting: AIResponses.RecipeSuggestionList.self) { list in
            list.recipes.contains(where: \.isUsable)
        }
        return result.map { $0.recipes.filter(\.isUsable) }
    }

    func recipesUsingUp(
        items: [PantryItem],
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<[AIResponses.RecipeSuggestion]> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        let request = AIPrompts.useItUp(
            context: context,
            itemNames: items.map(\.name),
            servings: preferences.defaultServings
        )
        let result = try await run(request, expecting: AIResponses.RecipeSuggestionList.self) { list in
            list.recipes.contains(where: \.isUsable)
        }
        return result.map { $0.recipes.filter(\.isUsable) }
    }

    func substitutions(
        for ingredient: String,
        recipeTitle: String?,
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<AIResponses.SubstitutionList> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        let request = AIPrompts.substitutions(context: context, ingredient: ingredient, recipeTitle: recipeTitle)
        return try await run(request, expecting: AIResponses.SubstitutionList.self) { $0.isUsable }
    }

    func mealPlan(
        startDate: Date,
        days: Int,
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<AIResponses.MealPlan> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        let request = AIPrompts.mealPlan(
            context: context,
            startDate: startDate,
            days: days,
            servings: preferences.defaultServings
        )
        return try await run(request, expecting: AIResponses.MealPlan.self) { $0.isUsable }
    }

    func shoppingAdvice(
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<AIResponses.ShoppingAdvice> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        return try await run(AIPrompts.shoppingAdvice(context: context), expecting: AIResponses.ShoppingAdvice.self) {
            $0.isUsable
        }
    }

    func inventoryAnalysis(
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<AIResponses.InventoryAnalysis> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        return try await run(AIPrompts.inventoryAnalysis(context: context), expecting: AIResponses.InventoryAnalysis.self) {
            $0.isUsable
        }
    }

    func leftoverIdeas(
        leftovers: String,
        inventory: [PantryItem],
        preferences: PreferenceSnapshot
    ) async throws -> AIResult<AIResponses.LeftoverIdeas> {
        let context = contextBuilder.context(inventory: inventory, preferences: preferences)
        let request = AIPrompts.leftoverIdeas(context: context, leftovers: leftovers)
        return try await run(request, expecting: AIResponses.LeftoverIdeas.self) { $0.isUsable }
    }

    // MARK: - Core

    /// Tries each available provider in turn. Within a provider, a response that decodes
    /// to the wrong shape earns exactly one stricter retry before moving on — models
    /// often recover on a second, blunter ask, but looping on a broken provider just
    /// makes the user wait.
    func run<T: Decodable>(
        _ request: AIRequest,
        expecting: T.Type,
        validate: (T) -> Bool = { _ in true }
    ) async throws -> AIResult<T> {

        var attemptedProviders: [String] = []
        var lastError: AIError = .noProviderAvailable

        for provider in providers {
            try Task.checkCancellation()
            guard await provider.isAvailable() else { continue }
            attemptedProviders.append(provider.name)

            for attempt in 1...2 {
                do {
                    var attemptRequest = request
                    if attempt == 2 {
                        attemptRequest.userPrompt += AIPrompts.stricterRetrySuffix
                        attemptRequest.temperature = max(0, request.temperature - 0.3)
                    }

                    let raw = try await provider.generate(attemptRequest)
                    let decoded = try JSONExtractor.decode(T.self, from: raw.text)

                    guard validate(decoded) else {
                        throw AIError.invalidResponse(detail: "The response was well-formed but unusable")
                    }

                    PantryLog.ai.info("\(request.kind.rawValue, privacy: .public) served by \(raw.providerName, privacy: .public)")
                    return AIResult(
                        value: decoded,
                        providerName: raw.providerName,
                        wasOnDevice: raw.wasOnDevice,
                        isSample: raw.providerName == sampleProviderName
                    )
                } catch let error as AIError {
                    lastError = error
                    if case .cancelled = error { throw error }
                    // Only a shape problem is worth asking the same provider again.
                    guard case .invalidResponse = error, attempt == 1 else { break }
                    PantryLog.ai.notice("Retrying \(provider.name, privacy: .public) with a stricter prompt")
                } catch is CancellationError {
                    throw AIError.cancelled
                } catch {
                    lastError = .server(status: 0, message: error.localizedDescription)
                    break
                }
            }
            PantryLog.ai.error("\(provider.name, privacy: .public) failed: \(lastError.localizedDescription, privacy: .public)")
        }

        if attemptedProviders.isEmpty { throw AIError.noProviderAvailable }
        // An offline failure is more useful to show than "everything failed".
        if case .offline = lastError { throw lastError }
        if attemptedProviders.count == 1 { throw lastError }
        throw AIError.allProvidersFailed(attemptedProviders)
    }
}

extension AIResult {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> AIResult<NewValue> {
        AIResult<NewValue>(
            value: transform(value),
            providerName: providerName,
            wasOnDevice: wasOnDevice,
            isSample: isSample
        )
    }
}
