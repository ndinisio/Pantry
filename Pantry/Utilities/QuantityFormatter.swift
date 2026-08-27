import Foundation

/// Formats quantities the way a person would write them: "6", "1.5 kg", "500 g".
enum QuantityFormatter {

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    static func number(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%g", value)
    }

    static func string(quantity: Double, unit: MeasurementUnit) -> String {
        let amount = number(quantity)
        // "6 eggs" reads better as just "6" next to the item's name.
        if unit == .piece {
            return amount
        }
        return "\(amount) \(unit.abbreviation)"
    }

    static func accessibleString(quantity: Double, unit: MeasurementUnit) -> String {
        let amount = number(quantity)
        if unit == .piece {
            return quantity == 1
                ? String(localized: "1 piece")
                : String(localized: "\(amount) pieces")
        }
        return "\(amount) \(unit.accessibleName)"
    }

    /// Clamps to zero and rounds countable units to whole numbers.
    static func normalise(_ quantity: Double, unit: MeasurementUnit) -> Double {
        let clamped = max(0, quantity)
        return unit.isCountable ? clamped.rounded() : (clamped * 100).rounded() / 100
    }
}
