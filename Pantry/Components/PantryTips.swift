import Foundation
import TipKit

/// Two tips, shown once, at the moment they are useful.
///
/// TipKit exists so a hint can appear in context and then never come back. That is the
/// only kind of guidance this app has — there is no onboarding sequence, because
/// nothing here needs explaining before it is used.
struct QuickAddTip: Tip {
    var title: Text {
        Text("Add several things at once")
    }
    var message: Text? {
        Text("Type or paste a list — \"milk, six eggs, 500g chicken\" — and Pantry sorts it out.")
    }
    var image: Image? {
        Image(systemName: "text.badge.plus")
    }
}

struct UseSoonTip: Tip {
    /// Only shown once the user has something that actually needs using.
    static let hasExpiringItems = Event(id: "hasExpiringItems")

    var title: Text {
        Text("Cook what needs using")
    }
    var message: Text? {
        Text("Tap an item here to see meals that use it up.")
    }
    var image: Image? {
        Image(systemName: "clock.badge")
    }
    var rules: [Rule] {
        #Rule(Self.hasExpiringItems) { $0.donations.count >= 1 }
    }
}
