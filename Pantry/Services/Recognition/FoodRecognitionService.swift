import Foundation
import Vision
import UIKit

/// Identifies likely foods in a photo, on device.
///
/// This is deliberately kept apart from the text AI layer: it uses Vision's image
/// classifier, so no photo ever leaves the device and there is no API to configure.
/// Results are always presented as candidates for the user to confirm, never added
/// automatically — an image classifier is confident far more often than it is right.
protocol FoodRecognising: Sendable {
    func recognise(imageData: Data) async throws -> [FoodCandidate]
}

/// One thing the classifier thinks it saw.
struct FoodCandidate: Identifiable, Hashable {
    let id = UUID()
    var name: String
    /// 0...1. Shown as a word rather than a percentage — a number implies precision
    /// this does not have.
    var confidence: Float
    var category: FoodCategory

    var confidenceDescription: String {
        switch confidence {
        case 0.6...: return String(localized: "Likely")
        case 0.35..<0.6: return String(localized: "Possible")
        default: return String(localized: "Maybe")
        }
    }
}

enum FoodRecognitionError: LocalizedError {
    case invalidImage
    case noFoodFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return String(localized: "That image couldn't be read")
        case .noFoodFound: return String(localized: "No food recognised")
        case .failed: return String(localized: "Recognition didn't work")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidImage: return String(localized: "Try a different photo.")
        case .noFoodFound: return String(localized: "Try a closer photo of one item, or add it by hand.")
        case .failed(let detail): return detail
        }
    }
}

/// Vision-backed implementation. Runs entirely on device.
struct VisionFoodRecognitionService: FoodRecognising {

    /// Minimum confidence worth showing at all.
    var minimumConfidence: Float = 0.12
    var maximumCandidates: Int = 8

    func recognise(imageData: Data) async throws -> [FoodCandidate] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw FoodRecognitionError.invalidImage
        }

        let observations = try await classify(cgImage: cgImage)

        let candidates = observations
            .filter { $0.confidence >= minimumConfidence }
            .compactMap { observation -> FoodCandidate? in
                let label = readable(observation.identifier)
                // The classifier knows thousands of things, most of which are not food.
                // Only labels that map to a known food category are offered.
                let category = CategoryGuesser.category(for: label)
                guard category != .other else { return nil }
                return FoodCandidate(name: label, confidence: observation.confidence, category: category)
            }
            .prefix(maximumCandidates)

        guard !candidates.isEmpty else { throw FoodRecognitionError.noFoodFound }
        return Array(candidates)
    }

    private func classify(cgImage: CGImage) async throws -> [VNClassificationObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: FoodRecognitionError.failed(error.localizedDescription))
                    return
                }
                let results = (request.results as? [VNClassificationObservation]) ?? []
                continuation.resume(returning: results)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: FoodRecognitionError.failed(error.localizedDescription))
            }
        }
    }

    /// Vision identifiers look like "bell_pepper" or "food, cheese".
    private func readable(_ identifier: String) -> String {
        let cleaned = identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: ",")
            .last
            .map(String.init) ?? identifier
        return cleaned
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
