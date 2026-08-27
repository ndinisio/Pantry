import Foundation

/// Units Pantry understands. Deliberately small: enough to describe a kitchen
/// without turning quantity entry into a unit-conversion exercise.
enum MeasurementUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case gram = "g"
    case kilogram = "kg"
    case millilitre = "ml"
    case litre = "L"
    case ounce = "oz"
    case pound = "lb"
    case piece
    case pack
    case can
    case bottle
    case jar
    case box
    case serving

    var id: String { rawValue }

    /// Short form shown next to a number, e.g. "500 g".
    var abbreviation: String {
        switch self {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .millilitre: return "ml"
        case .litre: return "L"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .piece: return String(localized: "pcs")
        case .pack: return String(localized: "packs")
        case .can: return String(localized: "cans")
        case .bottle: return String(localized: "bottles")
        case .jar: return String(localized: "jars")
        case .box: return String(localized: "boxes")
        case .serving: return String(localized: "servings")
        }
    }

    /// Spoken form for VoiceOver, where "g" would be read as the letter.
    var accessibleName: String {
        switch self {
        case .gram: return String(localized: "grams")
        case .kilogram: return String(localized: "kilograms")
        case .millilitre: return String(localized: "millilitres")
        case .litre: return String(localized: "litres")
        case .ounce: return String(localized: "ounces")
        case .pound: return String(localized: "pounds")
        default: return abbreviation
        }
    }

    /// Full name used in pickers.
    var name: String {
        switch self {
        case .gram: return String(localized: "Grams (g)")
        case .kilogram: return String(localized: "Kilograms (kg)")
        case .millilitre: return String(localized: "Millilitres (ml)")
        case .litre: return String(localized: "Litres (L)")
        case .ounce: return String(localized: "Ounces (oz)")
        case .pound: return String(localized: "Pounds (lb)")
        case .piece: return String(localized: "Pieces")
        case .pack: return String(localized: "Packs")
        case .can: return String(localized: "Cans")
        case .bottle: return String(localized: "Bottles")
        case .jar: return String(localized: "Jars")
        case .box: return String(localized: "Boxes")
        case .serving: return String(localized: "Servings")
        }
    }

    /// Countable units step by 1; measured units step by a sensible increment.
    var stepIncrement: Double {
        switch self {
        case .gram, .millilitre: return 50
        case .kilogram, .litre, .pound: return 0.25
        case .ounce: return 1
        default: return 1
        }
    }

    /// Whether a quantity of this unit is naturally a whole number.
    var isCountable: Bool {
        switch self {
        case .piece, .pack, .can, .bottle, .jar, .box, .serving: return true
        default: return false
        }
    }

    var isMass: Bool { self == .gram || self == .kilogram || self == .ounce || self == .pound }
    var isVolume: Bool { self == .millilitre || self == .litre }

    static func from(rawValue: String) -> MeasurementUnit {
        MeasurementUnit(rawValue: rawValue) ?? .piece
    }

    /// Units grouped for the picker so the list stays scannable.
    static let massUnits: [MeasurementUnit] = [.gram, .kilogram, .ounce, .pound]
    static let volumeUnits: [MeasurementUnit] = [.millilitre, .litre]
    static let countUnits: [MeasurementUnit] = [.piece, .pack, .can, .bottle, .jar, .box, .serving]
}
