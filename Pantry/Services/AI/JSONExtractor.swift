import Foundation

/// Pulls a JSON object out of a model's reply and decodes it.
///
/// Models sometimes wrap JSON in prose or a code fence even when asked not to. Rather
/// than failing the whole request over punctuation, this recovers the object — but it
/// never repairs the *contents*, so a genuinely malformed answer still fails loudly.
enum JSONExtractor {

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = jsonData(in: text) else {
            throw AIError.invalidResponse(detail: "No JSON object found in the response")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIError.invalidResponse(detail: error.localizedDescription)
        }
    }

    /// Returns the first balanced `{...}` block, ignoring braces inside string literals.
    static func jsonData(in text: String) -> Data? {
        let stripped = removeCodeFences(from: text)
        let characters = Array(stripped)

        guard let start = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var insideString = false
        var isEscaped = false

        for index in start..<characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                insideString.toggle()
                continue
            }
            guard !insideString else { continue }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(characters[start...index]).data(using: .utf8)
                }
            }
        }
        return nil
    }

    private static func removeCodeFences(from text: String) -> String {
        guard text.contains("```") else { return text }
        return text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
    }
}
