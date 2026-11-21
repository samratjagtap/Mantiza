import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: run what Mantiza suggests right now.
struct RunSuggestionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "run-suggestion") {
            ControlWidgetButton(action: RunSuggestedIntent()) {
                Label("Mantiza", systemImage: "hand.tap.fill")
            }
        }
        .displayName("Run Mantiza's suggestion")
        .description("Runs the workflow Mantiza suggests for this time of day.")
    }
}
