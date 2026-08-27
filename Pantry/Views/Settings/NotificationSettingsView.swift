import SwiftUI
import SwiftData
import UIKit

/// Reminder settings.
///
/// Two switches, one time. Permission is requested at the moment a switch is turned on
/// — never at launch — so the reason for the prompt is obvious. Turning everything off
/// cancels the schedule rather than leaving it pending.
struct NotificationSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\PantryItem.name)]) private var items: [PantryItem]
    @Query private var recipes: [Recipe]

    @State private var preferences: UserPreferences?
    @State private var showsPermissionDeniedNotice = false

    var body: some View {
        Form {
            if let preferences {
                content(for: preferences)
            }
        }
        .navigationTitle(Text("Reminders"))
        .onAppear {
            if preferences == nil {
                preferences = PantryModelContainer.preferences(in: modelContext)
            }
        }
        .task { await appEnvironment.notifications.refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private func content(for preferences: UserPreferences) -> some View {
        @Bindable var preferences = preferences

        Section {
            Toggle(isOn: Binding(
                get: { preferences.expiryNotificationsEnabled },
                set: { newValue in
                    Task { await set(expiry: newValue, on: preferences) }
                }
            )) {
                Label(String(localized: "Use Soon"), systemImage: "clock.badge")
            }

            Toggle(isOn: Binding(
                get: { preferences.mealIdeaNotificationsEnabled },
                set: { newValue in
                    Task { await set(mealIdeas: newValue, on: preferences) }
                }
            )) {
                Label(String(localized: "Dinner Ideas"), systemImage: "fork.knife")
            }
        } header: {
            Text("What to Send")
        } footer: {
            Text("At most one of each per day. Pantry won't remind you about food you've already used.")
        }

        if preferences.expiryNotificationsEnabled || preferences.mealIdeaNotificationsEnabled {
            Section {
                DatePicker(
                    String(localized: "Time"),
                    selection: Binding(
                        get: { dateFromMinutes(preferences.notificationTimeMinutes) },
                        set: { newValue in
                            preferences.notificationTimeMinutes = minutesFromDate(newValue)
                            persistAndReschedule(preferences)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            } header: {
                Text("When")
            } footer: {
                Text("Dinner ideas arrive an hour after the use-soon reminder.")
            }
        }

        if showsPermissionDeniedNotice {
            Section {
                Label(
                    String(localized: "Notifications are turned off for Pantry in iOS Settings."),
                    systemImage: "bell.slash"
                )
                .font(.footnote)
                Button(String(localized: "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func set(expiry isOn: Bool, on preferences: UserPreferences) async {
        if isOn, !(await ensureAuthorised()) { return }
        preferences.expiryNotificationsEnabled = isOn
        persistAndReschedule(preferences)
    }

    private func set(mealIdeas isOn: Bool, on preferences: UserPreferences) async {
        if isOn, !(await ensureAuthorised()) { return }
        preferences.mealIdeaNotificationsEnabled = isOn
        persistAndReschedule(preferences)
    }

    private func ensureAuthorised() async -> Bool {
        await appEnvironment.notifications.refreshAuthorizationStatus()
        if appEnvironment.notifications.isAuthorized { return true }
        if appEnvironment.notifications.authorizationStatus == .denied {
            showsPermissionDeniedNotice = true
            return false
        }
        let granted = await appEnvironment.notifications.requestAuthorization()
        showsPermissionDeniedNotice = !granted
        return granted
    }

    private func persistAndReschedule(_ preferences: UserPreferences) {
        preferences.lastUpdated = .now
        try? modelContext.save()
        appEnvironment.preferences = PreferenceSnapshot(preferences)

        let snapshot = PreferenceSnapshot(preferences)
        let readyTitle = RecipeMatcher.match(
            recipes: recipes,
            inventory: items,
            query: RecipeQuery(appetite: .useWhatIHave),
            preferences: snapshot,
            limit: 1
        ).first?.recipe.title

        let expiry = preferences.expiryNotificationsEnabled
        let ideas = preferences.mealIdeaNotificationsEnabled
        let time = preferences.notificationTimeMinutes
        let currentItems = items

        Task {
            await appEnvironment.notifications.reschedule(
                items: currentItems,
                preferences: snapshot,
                expiryEnabled: expiry,
                mealIdeasEnabled: ideas,
                notificationTimeMinutes: time,
                readyRecipeTitle: readyTitle
            )
        }
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? .now
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 19) * 60 + (components.minute ?? 0)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(AppEnvironment())
    .modelContainer(SampleData.previewContainer())
}
