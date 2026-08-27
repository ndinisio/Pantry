import Foundation

/// The whole contract between Pantry and any model.
///
/// Everything above this line — views, view models, services — is written against this
/// protocol and never against a vendor. Swapping providers is a change in one file.
protocol AIProvider: Sendable {
    /// Short identifier shown in Settings and in diagnostics, e.g. "On-device".
    var name: String { get }
    /// Whether the provider can serve a request right now (model downloaded, key set,
    /// network reachable). Checked before use so failures are explained, not guessed at.
    func isAvailable() async -> Bool
    /// Runs a request. Must throw rather than return a fabricated result.
    func generate(_ request: AIRequest) async throws -> AIRawResponse
}

/// One request to a model: a system instruction, a user prompt, and how the answer
/// should be shaped.
struct AIRequest: Sendable {
    /// What the model is being asked to do, in product terms.
    var kind: AIRequestKind
    /// Persona and rules. Stable per request kind.
    var systemPrompt: String
    /// The prompt, including the compact pantry context.
    var userPrompt: String
    /// When true the provider should ask for strict JSON.
    var expectsJSON: Bool = true
    var maxOutputTokens: Int = 1600
    var temperature: Double = 0.6
    /// Wall-clock budget for the whole request, including retries.
    var timeout: TimeInterval = 30
}

enum AIRequestKind: String, Sendable {
    case recipeSuggestions
    case useItUp
    case substitutions
    case mealPlan
    case shoppingAdvice
    case inventoryAnalysis
    case leftoverIdeas
}

/// The unparsed answer plus enough provenance to be honest in the UI about where it
/// came from.
struct AIRawResponse: Sendable {
    var text: String
    var providerName: String
    /// True when the answer was produced on device and no data left the phone.
    var wasOnDevice: Bool
}

/// Errors the UI can turn into something a person can act on.
enum AIError: LocalizedError, Equatable {
    case noProviderAvailable
    case notConfigured(providerName: String)
    case offline
    case timedOut
    case cancelled
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, message: String?)
    case invalidResponse(detail: String)
    case allProvidersFailed([String])

    var errorDescription: String? {
        switch self {
        case .noProviderAvailable:
            return String(localized: "No AI provider is set up")
        case .notConfigured(let providerName):
            return String(localized: "\(providerName) isn't set up yet")
        case .offline:
            return String(localized: "You're offline")
        case .timedOut:
            return String(localized: "That took too long")
        case .cancelled:
            return String(localized: "Cancelled")
        case .rateLimited:
            return String(localized: "Too many requests")
        case .server(let status, _):
            return String(localized: "The service returned an error (\(status))")
        case .invalidResponse:
            return String(localized: "The response couldn't be read")
        case .allProvidersFailed:
            return String(localized: "Couldn't reach any AI provider")
        }
    }

    /// One sentence telling the user what to do next. Never blames them.
    var recoverySuggestion: String? {
        switch self {
        case .noProviderAvailable, .notConfigured:
            return String(localized: "Set one up in Settings. Your pantry and saved recipes work without it.")
        case .offline:
            return String(localized: "Your pantry, saved recipes and shopping list still work offline.")
        case .timedOut:
            return String(localized: "Try again in a moment.")
        case .cancelled:
            return nil
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return String(localized: "Try again in about \(Int(retryAfter)) seconds.")
            }
            return String(localized: "Wait a moment and try again.")
        case .server:
            return String(localized: "This is usually temporary. Try again shortly.")
        case .invalidResponse:
            return String(localized: "Try again — the answer came back in an unexpected shape.")
        case .allProvidersFailed:
            return String(localized: "Check your connection, or use the recipes already in your library.")
        }
    }

    /// Whether retrying the same request could plausibly succeed.
    var isTransient: Bool {
        switch self {
        case .timedOut, .rateLimited, .server, .invalidResponse: return true
        default: return false
        }
    }
}
