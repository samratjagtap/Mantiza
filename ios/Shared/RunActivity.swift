import ActivityKit
import AppIntents
import Foundation

/// The Live Activity of a running task (lock screen and Dynamic Island).
struct RunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var step: Int
        var total: Int
        var action: String
        /// A risky step waiting for approval, e.g. "Send: tap Send?".
        var question: String?
        /// Set when the run has ended.
        var result: String?
        var paused = false
    }

    var goal: String
    /// Buttons act only on the run that started this activity (a stale one from an earlier run does nothing).
    var runID = ""
}

/// Hooks the app sets so the Live Activity buttons reach the running task (their intents run in the app's process).
@MainActor enum RunControl {
    static var stop: (String) -> Void = { _ in }
    static var pause: (String) -> Void = { _ in }
    static var answer: (Bool) -> Void = { _ in }
}

struct StopRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop task"
    @Parameter(title: "Run") var runID: String

    init() {}
    init(runID: String) { self.runID = runID }

    func perform() async throws -> some IntentResult {
        let id = runID
        await MainActor.run { RunControl.stop(id) }
        return .result()
    }
}

/// Pause or resume: the agent stops between actions and looks again before going on.
struct PauseRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume task"
    @Parameter(title: "Run") var runID: String

    init() {}
    init(runID: String) { self.runID = runID }

    func perform() async throws -> some IntentResult {
        let id = runID
        await MainActor.run { RunControl.pause(id) }
        return .result()
    }
}

struct AnswerApprovalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Answer approval"

    @Parameter(title: "Approve") var approve: Bool

    init() {}
    init(approve: Bool) { self.approve = approve }

    func perform() async throws -> some IntentResult {
        let yes = approve
        await MainActor.run { RunControl.answer(yes) }
        return .result()
    }
}
