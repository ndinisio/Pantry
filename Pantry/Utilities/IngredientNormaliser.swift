import Foundation

/// Turns free-text ingredient names into a stable key so "Tomatoes", "tomato" and
/// "  Fresh Tomato " all match each other.
///
/// Deliberately conservative: it lowercases, strips diacritics and punctuation,
/// removes a small set of descriptive words, and singularises common English plurals.
/// It never tries to be clever about compound foods — a wrong merge is worse than a miss.
enum IngredientNormaliser {

    /// Words that describe an ingredient without changing what it is.
    private static let noiseWords: Set<String> = [
        "fresh", "frozen", "dried", "raw", "cooked", "organic", "large", "small",
        "medium", "whole", "chopped", "sliced", "diced", "minced", "ground",
        "free", "range", "unsalted", "salted", "extra", "virgin", "plain", "of", "a", "an", "the"
    ]

    /// Plurals that a naive "-s" rule gets wrong.
    private static let irregularPlurals: [String: String] = [
        "leaves": "leaf",
        "loaves": "loaf",
        "potatoes": "potato",
        "tomatoes": "tomato",
        "chillies": "chilli",
        "berries": "berry",
        "cherries": "cherry",
        "anchovies": "anchovy",
        "knives": "knife"
    ]

    static func key(for name: String) -> String {
        let cleaned = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)

        let tokens = cleaned
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .map(singularise)
            .filter { !noiseWords.contains($0) && !$0.isEmpty }

        // Everything was noise ("fresh, chopped") — fall back to the cleaned string so
        // two different items never collapse onto an empty key.
        if tokens.isEmpty {
            return cleaned.trimmingCharacters(in: .whitespaces)
        }
        return tokens.joined(separator: " ")
    }

    private static func singularise(_ word: String) -> String {
        if let irregular = irregularPlurals[word] { return irregular }
        if word.count > 3, word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        if word.count > 3, word.hasSuffix("es"), word.hasSuffix("ses") || word.hasSuffix("xes") || word.hasSuffix("ches") || word.hasSuffix("shes") {
            return String(word.dropLast(2))
        }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }

    /// True when two names refer to the same thing, allowing one to contain the other
    /// ("chicken" matches "chicken breast", which is what a cook expects).
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = key(for: lhs)
        let b = key(for: rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return a.contains(b) || b.contains(a)
    }
}
