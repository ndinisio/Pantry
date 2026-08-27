import Testing
import Foundation
@testable import Pantry

@Suite("JSON extraction")
struct JSONExtractorTests {

    private struct Payload: Codable, Equatable {
        var title: String
        var count: Int
    }

    @Test("A bare JSON object decodes")
    func decodesPlainJSON() throws {
        let decoded = try JSONExtractor.decode(Payload.self, from: #"{"title":"Rice","count":2}"#)
        #expect(decoded == Payload(title: "Rice", count: 2))
    }

    @Test("A fenced object decodes")
    func decodesFencedJSON() throws {
        let text = """
        ```json
        {"title":"Rice","count":2}
        ```
        """
        #expect(try JSONExtractor.decode(Payload.self, from: text) == Payload(title: "Rice", count: 2))
    }

    @Test("An object wrapped in prose decodes")
    func decodesJSONInProse() throws {
        let text = "Sure! Here you go:\n{\"title\":\"Rice\",\"count\":2}\nHope that helps."
        #expect(try JSONExtractor.decode(Payload.self, from: text) == Payload(title: "Rice", count: 2))
    }

    @Test("Braces inside strings don't end the object early")
    func ignoresBracesInsideStrings() throws {
        let decoded = try JSONExtractor.decode(Payload.self, from: #"{"title":"Rice } with braces","count":2}"#)
        #expect(decoded.title == "Rice } with braces")
    }

    @Test("Escaped quotes inside strings are handled")
    func handlesEscapedQuotes() throws {
        let decoded = try JSONExtractor.decode(Payload.self, from: #"{"title":"He said \"hi\"","count":1}"#)
        #expect(decoded.title == #"He said "hi""#)
    }

    @Test("Text with no object fails rather than returning something invented")
    func failsWhenThereIsNoJSON() {
        #expect(throws: AIError.self) {
            try JSONExtractor.decode(Payload.self, from: "I'm afraid I can't do that.")
        }
    }

    @Test("Malformed JSON fails rather than being repaired")
    func failsOnMalformedJSON() {
        #expect(throws: AIError.self) {
            try JSONExtractor.decode(Payload.self, from: #"{"title":"Rice","count":}"#)
        }
    }
}

@Suite("Structured AI responses")
struct AIResponseTests {

    @Test("A complete recipe suggestion decodes and is usable")
    func decodesRecipeSuggestions() throws {
        let json = """
        {"recipes":[{"title":"Fried Rice","description":"Quick.","prepTimeMinutes":5,
        "cookTimeMinutes":10,"servings":2,"difficulty":"easy","tags":["quick"],
        "ingredients":[{"name":"Rice","quantity":200,"unit":"g"}],"steps":["Fry it."]}]}
        """
        let list = try JSONExtractor.decode(AIResponses.RecipeSuggestionList.self, from: json)
        let suggestion = try #require(list.recipes.first)
        #expect(suggestion.isUsable)
        #expect(suggestion.title == "Fried Rice")
    }

    @Test("Suggestions that decode but are unusable are rejected", arguments: [
        #"{"title":"","description":"","prepTimeMinutes":5,"cookTimeMinutes":5,"servings":2,"ingredients":[{"name":"Rice"}],"steps":["Go"]}"#,
        #"{"title":"X","description":"","prepTimeMinutes":5,"cookTimeMinutes":5,"servings":2,"ingredients":[],"steps":["Go"]}"#,
        #"{"title":"X","description":"","prepTimeMinutes":5,"cookTimeMinutes":5,"servings":2,"ingredients":[{"name":"Rice"}],"steps":[]}"#,
        #"{"title":"X","description":"","prepTimeMinutes":5,"cookTimeMinutes":5,"servings":0,"ingredients":[{"name":"Rice"}],"steps":["Go"]}"#,
        #"{"title":"X","description":"","prepTimeMinutes":5000,"cookTimeMinutes":5000,"servings":2,"ingredients":[{"name":"Rice"}],"steps":["Go"]}"#
    ])
    func rejectsUnusableSuggestions(json: String) throws {
        let suggestion = try JSONExtractor.decode(AIResponses.RecipeSuggestion.self, from: json)
        #expect(!suggestion.isUsable)
    }

    @Test("A suggestion converts into a recipe with its ingredients in order")
    func convertsToRecipe() throws {
        let json = """
        {"title":"Fried Rice","description":"Quick.","prepTimeMinutes":5,"cookTimeMinutes":10,
        "servings":2,"difficulty":"medium","tags":["quick"],
        "ingredients":[{"name":"Rice","quantity":200,"unit":"g"},{"name":"Egg","quantity":2,"unit":"piece","isOptional":true}],
        "steps":["Fry it."],"nutritionPerServing":{"calories":400,"proteinGrams":12}}
        """
        let recipe = try JSONExtractor.decode(AIResponses.RecipeSuggestion.self, from: json).makeRecipe()

        #expect(recipe.origin == .generated)
        #expect(recipe.difficulty == .medium)
        #expect(recipe.ingredients.count == 2)
        #expect(recipe.ingredients.first?.sortOrder == 0)
        #expect(recipe.ingredients.last?.isOptional == true)
        #expect(recipe.nutrition?.isEstimated == true)
        #expect(recipe.nutrition?.calories == 400)
    }

    @Test("An unknown unit falls back rather than failing the whole response")
    func toleratesUnknownUnits() throws {
        let json = #"{"title":"X","description":"","prepTimeMinutes":1,"cookTimeMinutes":1,"servings":1,"ingredients":[{"name":"Rice","quantity":1,"unit":"scoops"}],"steps":["Go"]}"#
        let recipe = try JSONExtractor.decode(AIResponses.RecipeSuggestion.self, from: json).makeRecipe()
        #expect(recipe.ingredients.first?.unit == .piece)
    }

    @Test("Empty structured payloads are treated as unusable")
    func rejectsEmptyPayloads() throws {
        #expect(try !JSONExtractor.decode(AIResponses.SubstitutionList.self, from: #"{"ingredient":"Butter","substitutions":[]}"#).isUsable)
        #expect(try !JSONExtractor.decode(AIResponses.MealPlan.self, from: #"{"days":[]}"#).isUsable)
        #expect(try !JSONExtractor.decode(AIResponses.LeftoverIdeas.self, from: #"{"ideas":[]}"#).isUsable)
        #expect(try !JSONExtractor.decode(AIResponses.InventoryAnalysis.self, from: #"{"summary":"  ","strengths":[],"gaps":[]}"#).isUsable)
    }
}

// MARK: - Provider doubles

/// A provider whose behaviour a test can dictate exactly.
private struct StubProvider: AIProvider {
    let name: String
    var available = true
    var responses: [Result<String, AIError>]
    /// Counts calls so tests can assert on retry and fallback behaviour.
    final class CallLog: @unchecked Sendable {
        var count = 0
        var prompts: [String] = []
    }
    let log = CallLog()

    func isAvailable() async -> Bool { available }

    func generate(_ request: AIRequest) async throws -> AIRawResponse {
        let index = min(log.count, responses.count - 1)
        log.count += 1
        log.prompts.append(request.userPrompt)
        switch responses[index] {
        case .success(let text):
            return AIRawResponse(text: text, providerName: name, wasOnDevice: false)
        case .failure(let error):
            throw error
        }
    }
}

@Suite("AI service orchestration")
struct AIServiceTests {

    private struct Payload: Decodable, Equatable {
        var title: String
    }

    private let request = AIRequest(kind: .recipeSuggestions, systemPrompt: "s", userPrompt: "p")

    @Test("The first available provider serves the request")
    func usesTheFirstAvailableProvider() async throws {
        let first = StubProvider(name: "First", responses: [.success(#"{"title":"A"}"#)])
        let second = StubProvider(name: "Second", responses: [.success(#"{"title":"B"}"#)])
        let service = AIService(providers: [first, second])

        let result = try await service.run(request, expecting: Payload.self)
        #expect(result.value.title == "A")
        #expect(result.providerName == "First")
        #expect(second.log.count == 0)
    }

    @Test("An unavailable provider is skipped without being called")
    func skipsUnavailableProviders() async throws {
        let unavailable = StubProvider(name: "Offline", available: false, responses: [.success(#"{"title":"A"}"#)])
        let available = StubProvider(name: "Ready", responses: [.success(#"{"title":"B"}"#)])
        let service = AIService(providers: [unavailable, available])

        let result = try await service.run(request, expecting: Payload.self)
        #expect(result.providerName == "Ready")
        #expect(unavailable.log.count == 0)
    }

    @Test("A failing provider falls through to the next one")
    func fallsBackOnFailure() async throws {
        let failing = StubProvider(name: "Broken", responses: [.failure(.server(status: 500, message: nil))])
        let working = StubProvider(name: "Groq", responses: [.success(#"{"title":"B"}"#)])
        let service = AIService(providers: [failing, working])

        let result = try await service.run(request, expecting: Payload.self)
        #expect(result.providerName == "Groq")
    }

    @Test("A bad shape earns exactly one stricter retry from the same provider")
    func retriesOnceWithAStricterPrompt() async throws {
        let provider = StubProvider(
            name: "Flaky",
            responses: [.success("not json at all"), .success(#"{"title":"A"}"#)]
        )
        let service = AIService(providers: [provider])

        let result = try await service.run(request, expecting: Payload.self)
        #expect(result.value.title == "A")
        #expect(provider.log.count == 2)
        #expect(provider.log.prompts.last?.contains("could not be parsed") == true)
    }

    @Test("A provider that never returns valid JSON is abandoned after the retry")
    func stopsRetryingAfterOneAttempt() async {
        let provider = StubProvider(name: "Broken", responses: [.success("nope")])
        let service = AIService(providers: [provider])

        await #expect(throws: AIError.self) {
            try await service.run(request, expecting: Payload.self)
        }
        #expect(provider.log.count == 2)
    }

    @Test("A well-formed but unusable answer is rejected, not shown")
    func rejectsUnusableAnswers() async {
        let provider = StubProvider(name: "Literal", responses: [.success(#"{"title":""}"#)])
        let service = AIService(providers: [provider])

        await #expect(throws: AIError.self) {
            try await service.run(request, expecting: Payload.self) { !$0.title.isEmpty }
        }
    }

    @Test("With nothing available the error says so rather than inventing a result")
    func reportsWhenNothingIsConfigured() async {
        let service = AIService(providers: [StubProvider(name: "None", available: false, responses: [])])
        await #expect(throws: AIError.noProviderAvailable) {
            try await service.run(request, expecting: Payload.self)
        }
    }

    @Test("Being offline is reported as offline, not as a generic failure")
    func surfacesOfflineOverGenericFailure() async {
        let first = StubProvider(name: "A", responses: [.failure(.server(status: 500, message: nil))])
        let second = StubProvider(name: "B", responses: [.failure(.offline)])
        let service = AIService(providers: [first, second])

        await #expect(throws: AIError.offline) {
            try await service.run(request, expecting: Payload.self)
        }
    }

    @Test("Sample provider output is flagged so the UI can label it")
    func flagsSampleResults() async throws {
        let sample = StubProvider(name: "Sample responses", responses: [.success(#"{"title":"A"}"#)])
        let service = AIService(providers: [sample], sampleProviderName: "Sample responses")

        let result = try await service.run(request, expecting: Payload.self)
        #expect(result.isSample)
    }

    @Test("Every request kind produces parseable sample content")
    func sampleProviderCoversEveryRequestKind() async throws {
        let provider = DemoProvider(latency: .zero)
        for kind in [AIRequestKind.recipeSuggestions, .useItUp, .substitutions, .mealPlan,
                     .shoppingAdvice, .inventoryAnalysis, .leftoverIdeas] {
            let response = try await provider.generate(
                AIRequest(kind: kind, systemPrompt: "s", userPrompt: "p")
            )
            #expect(JSONExtractor.jsonData(in: response.text) != nil, "\(kind.rawValue) produced no JSON")
        }
    }
}

@Suite("AI context")
struct AIContextTests {

    @Test("Inventory is capped and the omission is stated rather than hidden")
    func capsInventory() {
        let items = (1...100).map { PantryItem(name: "Item \($0)") }
        let builder = AIContextBuilder()
        let context = builder.context(inventory: items, preferences: .default)

        #expect(context.contains("more items not listed"))
        #expect(context.count < 4000)
    }

    @Test("Food that needs using is listed separately so the model can prioritise it")
    func highlightsExpiringItems() {
        let soon = PantryItem(
            name: "Spinach",
            expirationDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let later = PantryItem(
            name: "Rice",
            expirationDate: Calendar.current.date(byAdding: .day, value: 300, to: .now)
        )
        let context = AIContextBuilder().context(inventory: [soon, later], preferences: .default)

        #expect(context.contains("Expiring soon:"))
        #expect(context.contains("Spinach"))
    }

    @Test("Items with nothing left are not sent")
    func excludesEmptyItems() {
        let context = AIContextBuilder().context(
            inventory: [PantryItem(name: "Ghost", quantity: 0)],
            preferences: .default
        )
        #expect(!context.contains("Ghost"))
    }

    @Test("Allergies reach the model as a hard constraint")
    func includesAllergies() {
        var preferences = PreferenceSnapshot()
        preferences.allergies = ["Peanuts"]
        let context = AIContextBuilder().context(inventory: [PantryItem(name: "Rice")], preferences: preferences)
        #expect(context.contains("Must avoid"))
        #expect(context.contains("Peanuts"))
    }

    @Test("An empty pantry is described rather than sent as nothing")
    func describesAnEmptyPantry() {
        let context = AIContextBuilder().context(inventory: [], preferences: .default)
        #expect(context.contains("(empty)"))
    }
}
