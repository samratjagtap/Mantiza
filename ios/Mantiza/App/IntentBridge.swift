import AppIntents
import UIKit

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Siri, Shortcuts and Control Center → a run. There is no screen to fix things on when a run starts this way,
/// so everything it needs is checked first and a missing piece is named.
extension AppModel {
    func handleWorkflowRequest(_ id: String?) async -> String {
        Log.event("intent.run", ["workflow": id ?? "suggested"])
        let w = id.flatMap(UUID.init(uuidString:)).flatMap { workflows.workflow($0) } ?? (id == nil ? suggestion : nil)
        guard let w else { return id == nil ? "There is no suggestion right now." : "That workflow is gone." }
        let keys = (try? AISettings.bigBrain()) != nil
        if let problem = Self.intentProblem(running: runner.running, stick: boardConnected, pointer: inputReady, keys: keys,
                                            sessionLive: screen.live, appActive: UIApplication.shared.applicationState == .active) {
            Log.event("intent.refused", ["why": problem])
            return problem
        }
        Task { await run(w) }
        return "Started: \(w.name)."
    }

    /// What stops a run started from outside the app, in the order the user would fix it; nil when ready.
    nonisolated static func intentProblem(running: Bool, stick: Bool, pointer: Bool, keys: Bool, sessionLive: Bool,
                                          appActive: Bool) -> String? {
        if running { return "Mantiza is already working on a task." }
        if !stick { return "Mantiza Hands isn't connected. Turn the stick on and keep it near the phone." }
        if !pointer { return "The stick's pointer isn't paired. Open Mantiza's Device tab." }
        if !keys { return "Add your Anthropic key in Mantiza's Settings first." }
        if !sessionLive && !appActive { return "Open Mantiza and tap Start session, then ask again." }
        return nil
    }
}

/// "Run <workflow> in Mantiza" for Siri and Spotlight.
struct MantizaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunWorkflowIntent(), phrases: ["Run \(\.$workflow) in \(.applicationName)",
                                                           "Do \(\.$workflow) with \(.applicationName)"],
                    shortTitle: "Run Workflow", systemImageName: "hand.tap")
        AppShortcut(intent: RunSuggestedIntent(), phrases: ["Run the \(.applicationName) suggestion"],
                    shortTitle: "Run Suggestion", systemImageName: "sparkles")
    }
}
