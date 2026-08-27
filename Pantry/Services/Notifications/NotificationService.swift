import Foundation
import UserNotifications
import Observation
import OSLog

/// Sparse, useful notifications.
///
/// Two kinds only: something needs using, and there is a dinner you could make from
/// what you already have. Both are opt-in, both are a single daily notification at a
/// time the user chooses, and neither is scheduled until permission is granted in
/// context — never at launch.
@Observable
final class NotificationService {

    enum Identifier {
        static let useSoon = "pantry.use-soon"
        static let mealIdea = "pantry.meal-idea"
    }

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter { .current() }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Asked for at the moment the user turns a reminder on, so the reason is obvious.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            PantryLog.notifications.error("Authorisation request failed: \(error.localizedDescription, privacy: .public)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Rebuilds the schedule from scratch. Called whenever inventory or preferences
    /// change, so a stale reminder never fires for food that has already been eaten.
    func reschedule(
        items: [PantryItem],
        preferences: PreferenceSnapshot,
        expiryEnabled: Bool,
        mealIdeasEnabled: Bool,
        notificationTimeMinutes: Int,
        readyRecipeTitle: String?
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.useSoon, Identifier.mealIdea])
        guard isAuthorized else { return }

        if expiryEnabled {
            let expiring = items.filter {
                ExpirationCalculator
                    .freshness(for: $0.expirationDate, useSoonWindowDays: preferences.useSoonWindowDays)
                    .isNoteworthy
            }
            if !expiring.isEmpty {
                await schedule(
                    identifier: Identifier.useSoon,
                    title: String(localized: "Use soon"),
                    body: useSoonBody(for: expiring),
                    minutesFromMidnight: notificationTimeMinutes,
                    route: .useSoon
                )
            }
        }

        if mealIdeasEnabled, let readyRecipeTitle {
            await schedule(
                identifier: Identifier.mealIdea,
                title: String(localized: "Dinner idea"),
                body: String(localized: "You have everything for \(readyRecipeTitle)."),
                // Offset by an hour so the two reminders never arrive together.
                minutesFromMidnight: (notificationTimeMinutes + 60) % (24 * 60),
                route: .whatCanIMake
            )
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.useSoon, Identifier.mealIdea])
    }

    // MARK: - Private

    private func useSoonBody(for items: [PantryItem]) -> String {
        let names = items.prefix(3).map(\.name)
        switch items.count {
        case 1:
            return String(localized: "Your \(names[0].lowercased()) is approaching its date.")
        case 2:
            return String(localized: "\(names[0]) and \(names[1]) are approaching their dates.")
        default:
            let extra = items.count - 2
            return String(localized: "\(names[0]), \(names[1]) and \(extra) more are approaching their dates.")
        }
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        minutesFromMidnight: Int,
        route: AppRoute
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .passive
        if let url = DeepLink.url(for: route) {
            content.userInfo = ["route": url.absoluteString]
        }

        var components = DateComponents()
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        do {
            try await center.add(request)
        } catch {
            PantryLog.notifications.error("Could not schedule \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
