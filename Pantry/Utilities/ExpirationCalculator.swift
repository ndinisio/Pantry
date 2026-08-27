import Foundation

/// How close an item is to its date.
///
/// Language is deliberately calm: an expiration date is a reminder to use something,
/// not a verdict on whether it is safe. Nothing here says "spoiled" or "unsafe".
enum FreshnessState: Int, Comparable, Sendable {
    case past = 0
    case today = 1
    case useSoon = 2
    case fresh = 3
    case unknown = 4

    static func < (lhs: FreshnessState, rhs: FreshnessState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbolName: String {
        switch self {
        case .past: return "clock.badge.exclamationmark"
        case .today: return "clock.badge"
        case .useSoon: return "clock"
        case .fresh: return "checkmark.circle"
        case .unknown: return "calendar.badge.questionmark"
        }
    }

    /// Whether this state deserves a visible marker in a list row.
    var isNoteworthy: Bool { self == .past || self == .today || self == .useSoon }
}

enum ExpirationCalculator {

    /// Days from today until `date`, negative when the date has passed.
    static func daysUntil(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    static func freshness(
        for date: Date?,
        useSoonWindowDays: Int = 3,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FreshnessState {
        guard let days = daysUntil(date, now: now, calendar: calendar) else { return .unknown }
        if days < 0 { return .past }
        if days == 0 { return .today }
        if days <= useSoonWindowDays { return .useSoon }
        return .fresh
    }

    /// Short, human phrasing: "Today", "Tomorrow", "In 3 days", "3 days ago".
    static func relativeDescription(
        for date: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let days = daysUntil(date, now: now, calendar: calendar) else { return nil }
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        case let d where d > 1 && d <= 14: return String(localized: "In \(d) days")
        case let d where d < -1 && d >= -14: return String(localized: "\(abs(d)) days ago")
        default:
            return date?.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// Row subtitle, e.g. "Use by tomorrow" or "Best before 12 Sep".
    static func statusDescription(
        for date: Date?,
        useSoonWindowDays: Int = 3,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let date else { return nil }
        let state = freshness(for: date, useSoonWindowDays: useSoonWindowDays, now: now, calendar: calendar)
        guard let relative = relativeDescription(for: date, now: now, calendar: calendar) else { return nil }
        switch state {
        case .past: return String(localized: "Date passed \(relative.lowercased())")
        case .today: return String(localized: "Use today")
        case .useSoon: return String(localized: "Use by \(relative.lowercased())")
        case .fresh, .unknown: return String(localized: "Best before \(relative.lowercased())")
        }
    }

    /// A default date offered when the user adds an item without one.
    static func suggestedExpiration(
        for category: FoodCategory,
        from date: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let days = category.typicalShelfLifeDays else { return nil }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
    }
}
