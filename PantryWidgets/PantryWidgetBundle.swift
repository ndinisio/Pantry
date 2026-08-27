import WidgetKit
import SwiftUI

/// Pantry's widgets.
///
/// This is the entry point of the `PantryWidgets` app extension, which is a separate
/// target with its own bundle identifier. It shares the App Group in
/// `PantryWidgets.entitlements` with the app, and reads the summary the app writes
/// there through `WidgetSnapshotStore` in `Shared/`.
@main
struct PantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        PantryStatusWidget()
    }
}
