import Foundation

/// Converts between units within the same dimension. Returns `nil` rather than
/// guessing when a conversion isn't meaningful — 200 g of rice is not "a pack".
enum UnitConverter {

    private static let gramsPerUnit: [MeasurementUnit: Double] = [
        .gram: 1,
        .kilogram: 1000,
        .ounce: 28.3495,
        .pound: 453.592
    ]

    private static let millilitresPerUnit: [MeasurementUnit: Double] = [
        .millilitre: 1,
        .litre: 1000
    ]

    static func convert(_ value: Double, from source: MeasurementUnit, to target: MeasurementUnit) -> Double? {
        if source == target { return value }
        if let from = gramsPerUnit[source], let to = gramsPerUnit[target] {
            return value * from / to
        }
        if let from = millilitresPerUnit[source], let to = millilitresPerUnit[target] {
            return value * from / to
        }
        return nil
    }

    /// True when two units describe the same kind of measurement.
    static func areCompatible(_ lhs: MeasurementUnit, _ rhs: MeasurementUnit) -> Bool {
        if lhs == rhs { return true }
        if lhs.isMass && rhs.isMass { return true }
        if lhs.isVolume && rhs.isVolume { return true }
        return false
    }
}
