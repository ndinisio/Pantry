import WidgetKit
import SwiftUI
import AppIntents

/// What is in the pantry, what needs using, and what could be cooked tonight.
///
/// One widget in three sizes rather than three widgets: the question is the same at
/// every size, and the answer just gets more detailed as there is room for it. A widget
/// per feature would clutter the gallery for no gain.
struct PantryStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: PantryTimelineProvider()) { entry in
            PantryStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pantry")
        .description("What you have, what needs using, and what you could cook.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PantryEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct PantryTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> PantryEntry {
        PantryEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                totalItems: 47,
                expiringSoon: 3,
                shoppingCount: 5,
                useSoonNames: ["Strawberries", "Chicken", "Spinach"],
                suggestedRecipeTitle: "Chicken Fried Rice",
                suggestedRecipeMinutes: 25,
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PantryEntry) -> Void) {
        completion(PantryEntry(date: .now, snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PantryEntry>) -> Void) {
        let entry = PantryEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // The app reloads timelines whenever the pantry changes, so this refresh is
        // only a safety net for dates rolling over at midnight.
        let nextMidnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct PantryStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PantryEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pantry", systemImage: "cabinet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(snapshot.totalItems)")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())

            Text(snapshot.totalItems == 1 ? "item" : "items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if snapshot.expiringSoon > 0 {
                Label("\(snapshot.expiringSoon) to use soon", systemImage: "clock.badge")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if snapshot.shoppingCount > 0 {
                Label("\(snapshot.shoppingCount) to buy", systemImage: "cart")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "pantry://use-soon"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pantry", systemImage: "cabinet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(snapshot.totalItems)")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text(snapshot.totalItems == 1 ? "item" : "items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if snapshot.shoppingCount > 0 {
                    Label("\(snapshot.shoppingCount) to buy", systemImage: "cart")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 90, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let title = snapshot.suggestedRecipeTitle {
                    Text("Tonight")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    if let minutes = snapshot.suggestedRecipeMinutes {
                        Text("\(minutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !snapshot.useSoonNames.isEmpty {
                    Text("Use soon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(snapshot.useSoonNames.prefix(3), id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                } else {
                    Text("Nothing needs using")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "pantry://what-can-i-make"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            if snapshot.expiringSoon > 0 {
                Text("\(snapshot.expiringSoon) to use soon")
                    .font(.headline)
                Text(snapshot.useSoonNames.prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(1)
            } else if let title = snapshot.suggestedRecipeTitle {
                Text("Tonight")
                    .font(.caption)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Text("Pantry")
                    .font(.headline)
                Text("\(snapshot.totalItems) items")
                    .font(.caption)
            }
        }
        .widgetURL(URL(string: "pantry://use-soon"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(snapshot.totalItems) items in your pantry"]
        if snapshot.expiringSoon > 0 {
            parts.append("\(snapshot.expiringSoon) to use soon")
        }
        if let title = snapshot.suggestedRecipeTitle {
            parts.append("Tonight, \(title)")
        }
        if snapshot.shoppingCount > 0 {
            parts.append("\(snapshot.shoppingCount) on your shopping list")
        }
        return parts.joined(separator: ". ")
    }
}
