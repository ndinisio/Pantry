import Foundation

/// Groq, used as the fallback when the on-device model is unavailable.
///
/// The key is read from the Keychain (or a scheme environment variable during
/// development) — never from source, never from Info.plist, never from the repository.
/// See `SecretStore` and the security notes in the README.
struct GroqProvider: AIProvider {

    let name = String(localized: "Groq")

    var model: String = "llama-3.3-70b-versatile"
    var endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    var client: HTTPClient

    init(client: HTTPClient = HTTPClient(timeout: 30)) {
        self.client = client
    }

    func isAvailable() async -> Bool {
        SecretStore.hasValue(for: .groqAPIKey)
    }

    func generate(_ request: AIRequest) async throws -> AIRawResponse {
        guard let apiKey = SecretStore.value(for: .groqAPIKey) else {
            throw AIError.notConfigured(providerName: name)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body(for: request))

        let data = try await client.send(urlRequest)
        let completion = try decode(data)

        guard let text = completion.choices.first?.message.content, !text.isEmpty else {
            throw AIError.invalidResponse(detail: "The response contained no content")
        }
        return AIRawResponse(text: text, providerName: name, wasOnDevice: false)
    }

    // MARK: - Wire format

    private func body(for request: AIRequest) -> ChatRequest {
        ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: request.systemPrompt),
                .init(role: "user", content: request.userPrompt)
            ],
            temperature: request.temperature,
            maxCompletionTokens: request.maxOutputTokens,
            responseFormat: request.expectsJSON ? .init(type: "json_object") : nil
        )
    }

    private func decode(_ data: Data) throws -> ChatResponse {
        do {
            return try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse(detail: error.localizedDescription)
        }
    }

    struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var temperature: Double
        var maxCompletionTokens: Int
        var responseFormat: ResponseFormat?

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxCompletionTokens = "max_completion_tokens"
            case responseFormat = "response_format"
        }

        struct Message: Encodable {
            var role: String
            var content: String
        }

        struct ResponseFormat: Encodable {
            var type: String
        }
    }

    struct ChatResponse: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var message: Message
            struct Message: Decodable {
                var content: String?
            }
        }
    }
}
