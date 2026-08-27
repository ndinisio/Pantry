import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, tried before anything leaves the device.
///
/// When this is available the user's inventory never goes to a server, there is no key
/// to configure and no per-request cost. It is the preferred provider for exactly those
/// reasons, and everything else in the AI stack is a fallback for when it isn't there.
///
/// The whole framework surface is confined to this one file behind `canImport`, so a
/// build against an SDK without FoundationModels still compiles — the provider simply
/// reports itself unavailable and `AIService` moves on to the next one.
struct FoundationModelsProvider: AIProvider {

    let name = String(localized: "On-device")

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        return false
        #else
        return false
        #endif
    }

    /// Why the on-device model can't be used, for Settings.
    func unavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return String(localized: "This device doesn't support on-device intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return String(localized: "Turn on Apple Intelligence in Settings to use the on-device model.")
            case .unavailable(.modelNotReady):
                return String(localized: "The on-device model is still downloading.")
            case .unavailable:
                return String(localized: "The on-device model isn't available right now.")
            }
        }
        return String(localized: "Requires iOS 26 or later.")
        #else
        return String(localized: "Not available in this build.")
        #endif
    }

    func generate(_ request: AIRequest) async throws -> AIRawResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard await isAvailable() else {
                throw AIError.notConfigured(providerName: name)
            }
            do {
                let session = LanguageModelSession(instructions: request.systemPrompt)
                let response = try await session.respond(to: request.userPrompt)
                let text = response.content
                guard !text.isEmpty else {
                    throw AIError.invalidResponse(detail: "The on-device model returned nothing")
                }
                return AIRawResponse(text: text, providerName: name, wasOnDevice: true)
            } catch let error as AIError {
                throw error
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                throw AIError.server(status: 0, message: error.localizedDescription)
            }
        }
        throw AIError.notConfigured(providerName: name)
        #else
        throw AIError.notConfigured(providerName: name)
        #endif
    }
}
