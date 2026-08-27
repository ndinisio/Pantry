import Foundation

/// Talks to a backend the user controls, which holds the model credential.
///
/// This is the shape to use beyond personal development:
///
///     iOS app  →  your backend  →  model provider
///
/// The app then ships no provider secret at all. The proxy is expected to accept
/// `{ "system": "...", "prompt": "...", "json": true }` and return `{ "text": "..." }`.
struct ProxyProvider: AIProvider {

    let name = String(localized: "Secure proxy")
    var client: HTTPClient

    init(client: HTTPClient = HTTPClient(timeout: 30)) {
        self.client = client
    }

    func isAvailable() async -> Bool {
        guard let raw = SecretStore.value(for: .proxyURL) else { return false }
        return URL(string: raw)?.scheme?.lowercased() == "https"
    }

    func generate(_ request: AIRequest) async throws -> AIRawResponse {
        guard let raw = SecretStore.value(for: .proxyURL), let url = URL(string: raw) else {
            throw AIError.notConfigured(providerName: name)
        }
        // Plain HTTP would put the prompt and any token on the wire in the clear.
        guard url.scheme?.lowercased() == "https" else {
            throw AIError.notConfigured(providerName: name)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SecretStore.value(for: .proxyToken) {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            Body(
                kind: request.kind.rawValue,
                system: request.systemPrompt,
                prompt: request.userPrompt,
                json: request.expectsJSON,
                maxOutputTokens: request.maxOutputTokens,
                temperature: request.temperature
            )
        )

        let data = try await client.send(urlRequest)
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIError.invalidResponse(detail: error.localizedDescription)
        }
        guard !response.text.isEmpty else {
            throw AIError.invalidResponse(detail: "The proxy returned no content")
        }
        return AIRawResponse(text: response.text, providerName: name, wasOnDevice: false)
    }

    struct Body: Encodable {
        var kind: String
        var system: String
        var prompt: String
        var json: Bool
        var maxOutputTokens: Int
        var temperature: Double
    }

    struct Response: Decodable {
        var text: String
    }
}
