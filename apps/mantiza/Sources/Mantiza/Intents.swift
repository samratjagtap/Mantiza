import AppIntents
import MantizaKit

// Mantiza's actions for Siri, the Shortcuts app, Control Centre and the Live Activity.
//
// This file is compiled into the app AND the widget (scripts/make_secrets.py copies it to
// Sources/MantizaWidget/Intents.swift before every build): iOS needs the action's type in the
// bundle that shows its button, and runs it in the app.
//
// Keep these simple. iOS only lists actions from an index (Metadata.appintents) that Apple's
// Mac-only tool writes; off a Mac, scripts/make_intents.py writes it with an open-source stand-in
// that covers plain titles and parameters of basic types. Anything fancier is refused there.

/// "Ask Mantiza": Siri asks what to do, then Mantiza opens and does it. Also the Shortcuts action
/// for automations ("when I get home, ask Mantiza to …").
struct AskMantizaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Mantiza"
    static let description = IntentDescription("Mantiza does what you ask on this iPhone.")
    static let openAppWhenRun = true

    @Parameter(title: "Request")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.shared.post(.run(request))
        return .result()
    }
}

/// "Talk to Mantiza": opens Mantiza already listening. Used by the Control Centre / Lock Screen /
/// Action Button control.
struct ListenIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Mantiza"
    static let description = IntentDescription("Opens Mantiza ready to listen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.shared.post(.listen)
        return .result()
    }
}

/// Stops the running task without opening Mantiza (the Stop button on the Live Activity).
struct StopTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Mantiza"
    static let description = IntentDescription("Stops the task Mantiza is doing.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.shared.post(.stop)
        return .result()
    }
}
