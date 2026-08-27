import SwiftUI

/// Quantity editing built on the native `Stepper`, so the increment and decrement
/// buttons keep system hit targets, repeat-on-hold, VoiceOver behaviour and the
/// platform's own look. Only the label is ours.
///
/// The step size follows the unit — eggs go up by one, flour by fifty grams — because
/// making someone tap "+1 g" fifty times is not a quantity control.
struct QuantityStepper: View {
    @Binding var quantity: Double
    var unit: MeasurementUnit
    /// Shown to the left of the value. Omit inside a row that already names the item.
    var title: String?

    private var step: Double { unit.stepIncrement }

    var body: some View {
        Stepper(
            value: $quantity,
            in: 0...100_000,
            step: step
        ) {
            HStack {
                if let title {
                    Text(title)
                }
                Spacer(minLength: 8)
                Text(QuantityFormatter.string(quantity: quantity, unit: unit))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityLabel(title ?? String(localized: "Quantity"))
        .accessibilityValue(QuantityFormatter.accessibleString(quantity: quantity, unit: unit))
    }
}

/// The compact form used in a list row, where the item's name is already the row's
/// label. Uses plain buttons so the whole row stays a single, sensible VoiceOver stop
/// with two adjustment actions rather than three separate elements.
struct InlineQuantityStepper: View {
    var quantity: Double
    var unit: MeasurementUnit
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(quantity <= 0)
            .accessibilityLabel(String(localized: "Decrease quantity"))

            Text(QuantityFormatter.string(quantity: quantity, unit: unit))
                .font(.subheadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 44)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Increase quantity"))
        }
    }
}

#Preview("Quantity controls") {
    @Previewable @State var eggs: Double = 6
    @Previewable @State var flour: Double = 500

    List {
        Section {
            QuantityStepper(quantity: $eggs, unit: .piece, title: "Eggs")
            QuantityStepper(quantity: $flour, unit: .gram, title: "Flour")
        }
        Section {
            HStack {
                Text("Milk")
                Spacer()
                InlineQuantityStepper(quantity: 2, unit: .litre, onDecrement: {}, onIncrement: {})
            }
        }
    }
}
