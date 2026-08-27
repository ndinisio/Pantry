import Foundation

/// Turns a sentence like "I bought 2 litres of milk, a pack of chicken breasts and six
/// eggs" into pantry items.
///
/// Deliberately deterministic: it runs instantly, offline, and produces the same result
/// every time. The AI layer can improve on it, but the app never depends on that.
enum NaturalLanguageItemParser {

    struct ParsedItem: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: MeasurementUnit
        var category: FoodCategory

        func makePantryItem() -> PantryItem {
            PantryItem(
                name: name,
                category: category,
                quantity: quantity,
                unit: unit,
                expirationDate: ExpirationCalculator.suggestedExpiration(for: category)
            )
        }
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "dozen": 12, "half": 0.5, "couple": 2
    ]

    /// Words that introduce a quantity but are not part of the food's name.
    private static let unitWords: [String: MeasurementUnit] = [
        "g": .gram, "gram": .gram, "grams": .gram, "gramme": .gram, "grammes": .gram,
        "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
        "ml": .millilitre, "millilitre": .millilitre, "millilitres": .millilitre, "milliliter": .millilitre, "milliliters": .millilitre,
        "l": .litre, "litre": .litre, "litres": .litre, "liter": .litre, "liters": .litre,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "pack": .pack, "packs": .pack, "packet": .pack, "packets": .pack,
        "can": .can, "cans": .can, "tin": .can, "tins": .can,
        "bottle": .bottle, "bottles": .bottle,
        "jar": .jar, "jars": .jar,
        "box": .box, "boxes": .box,
        "serving": .serving, "servings": .serving,
        "piece": .piece, "pieces": .piece
    ]

    /// Phrases people put at the start of a sentence that carry no inventory meaning.
    private static let leadingNoise = [
        "i bought", "i just bought", "i have got", "i have", "i've got", "i got",
        "add", "picked up", "i picked up", "bought", "we have", "we bought", "there is", "there are"
    ]

    private static let connectorWords: Set<String> = ["of", "and", "plus", "with", "some"]

    static func parse(_ input: String) -> [ParsedItem] {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for noise in leadingNoise where text.hasPrefix(noise) {
            text = String(text.dropFirst(noise.count))
            break
        }

        let fragments = text
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return fragments.compactMap(parseFragment)
    }

    /// Parses one fragment, e.g. "2 litres of milk" or "six eggs".
    static func parseFragment(_ fragment: String) -> ParsedItem? {
        var tokens = fragment
            .replacingOccurrences(of: "[^a-z0-9. ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var quantity: Double?
        var unit: MeasurementUnit?

        // A leading "500g" with no space is common enough to be worth handling.
        if let first = tokens.first, let split = splitNumberAndUnit(first) {
            quantity = split.value
            unit = split.unit
            tokens.removeFirst()
        }

        if quantity == nil, let first = tokens.first {
            if let value = Double(first) {
                quantity = value
                tokens.removeFirst()
            } else if let value = numberWords[first] {
                quantity = value
                tokens.removeFirst()
            }
        }

        if unit == nil, let first = tokens.first, let matched = unitWords[first] {
            unit = matched
            tokens.removeFirst()
        }

        // Drop connectors left over between the quantity and the food.
        while let first = tokens.first, connectorWords.contains(first) {
            tokens.removeFirst()
        }

        let name = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let displayName = name
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        let category = CategoryGuesser.category(for: displayName)
        let resolvedUnit = unit ?? CategoryGuesser.unit(for: displayName)

        return ParsedItem(
            name: displayName,
            quantity: QuantityFormatter.normalise(quantity ?? 1, unit: resolvedUnit),
            unit: resolvedUnit,
            category: category
        )
    }

    /// "500g" → (500, .gram). Returns nil when the token isn't of that shape.
    private static func splitNumberAndUnit(_ token: String) -> (value: Double, unit: MeasurementUnit)? {
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty else { return nil }
        let suffix = String(token.dropFirst(digits.count))
        guard !suffix.isEmpty, let unit = unitWords[suffix], let value = Double(digits) else { return nil }
        return (value, unit)
    }

    /// Quick Add: one item per line, no sentence structure expected.
    static func parseLines(_ input: String) -> [ParsedItem] {
        input
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { parseFragment($0.lowercased()) }
    }
}
