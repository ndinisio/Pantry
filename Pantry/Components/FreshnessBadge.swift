import SwiftUI

/// The marker shown against an item that needs using.
///
/// Colour is never the only signal: every state carries a symbol and a word, so the
/// meaning survives greyscale, colour blindness and VoiceOver.
struct FreshnessBadge: View {
    var state: FreshnessState
    var date: Date?
    var useSoonWindowDays: Int = 3
    /// Compact form drops the text and keeps the symbol, for dense rows.
    var isCompact: Bool = false

    private var text: String? {
        ExpirationCalculator.relativeDescription(for: date)
    }

    private var tint: Color {
        switch state {
        case .past: return .orange
        case .today: return .orange
        case .useSoon: return .yellow
        case .fresh: return .secondary
        case .unknown: return .secondary
        }
    }

    var body: some View {
        if state.isNoteworthy, let text {
            Label {
                if !isCompact {
                    Text(text)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } icon: {
                Image(systemName: state.symbolName)
                    .font(.caption)
            }
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                ExpirationCalculator.statusDescription(for: date, useSoonWindowDays: useSoonWindowDays)
                    ?? text
            )
        }
    }
}

/// The category glyph used down the leading edge of pantry rows. Gives each row a
/// recognisable shape at a glance without turning the list into a colour chart.
struct CategoryGlyph: View {
    var category: FoodCategory
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.5))
            .foregroundStyle(category.tint)
            .frame(width: size, height: size)
            .background(category.tint.opacity(0.12), in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

#Preview("Freshness") {
    List {
        FreshnessBadge(state: .past, date: .now.addingTimeInterval(-86_400))
        FreshnessBadge(state: .today, date: .now)
        FreshnessBadge(state: .useSoon, date: .now.addingTimeInterval(2 * 86_400))
        HStack(spacing: 12) {
            ForEach(FoodCategory.allCases) { category in
                CategoryGlyph(category: category)
            }
        }
    }
}
