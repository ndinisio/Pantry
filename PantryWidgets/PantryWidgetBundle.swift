import WidgetKit
import SwiftUI

/// Pantry's widgets.
///
/// These files are not in the app target — a widget extension is a separate target
/// with its own bundle identifier and an App Group capability, and that has to be set
/// up in Xcode rather than generated. See "Adding the widget extension" in the README
/// for the four steps. The code is complete and compiles as soon as the target exists.
@main
struct PantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        PantryStatusWidget()
    }
}
