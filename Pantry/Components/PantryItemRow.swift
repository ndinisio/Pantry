import SwiftUI

/// A single item in the inventory list.
///
/// One VoiceOver stop reading "Greek Yogurt, 500 grams, use by tomorrow, opened",
/// rather than five fragments — the quantity controls are exposed as custom actions
/// instead, which is how a native list row behaves.
struct PantryItemRow: View {
    var item: PantryItem
    var useSoonWindowDays: Int = 3
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?

    private var freshness: FreshnessState {
        ExpirationCalculator.freshness(for: item.expirationDate, useSoonWindowDays: useSoonWindowDays)
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(category: item.category)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(2)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.quantityDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if freshness.isNoteworthy {
                        FreshnessBadge(state: freshness, date: item.expirationDate, useSoonWindowDays: useSoonWindowDays)
                            .accessibilityHidden(true)
                    }

                    if item.isOpened {
                        Text(String(localized: "Opened"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if let location = item.location {
                Image(systemName: location.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            if let onIncrement {
                Button(String(localized: "Increase quantity"), action: onIncrement)
            }
            if let onDecrement {
                Button(String(localized: "Decrease quantity"), action: onDecrement)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.name, item.accessibleQuantityDescription]
        if let status = ExpirationCalculator.statusDescription(for: item.expirationDate, useSoonWindowDays: useSoonWindowDays) {
            parts.append(status)
        }
        if item.isOpened { parts.append(String(localized: "Opened")) }
        if let location = item.location { parts.append(location.name) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    List {
        PantryItemRow(item: PantryItem(name: "Greek Yogurt", category: .dairy, quantity: 500, unit: .gram,
                                       expirationDate: .now.addingTimeInterval(86_400), location: .fridge, isOpened: true))
        PantryItemRow(item: PantryItem(name: "Rice", category: .grains, quantity: 1, unit: .kilogram,
                                       location: .cupboard))
        PantryItemRow(item: PantryItem(name: "Strawberries", category: .produce, quantity: 250, unit: .gram,
                                       expirationDate: .now, location: .fridge, isPinned: true))
    }
}
