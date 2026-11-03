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
    }

    var goal: String
}

/// Hooks the app sets so the Live Activity buttons reach the running task (their intents run in the app's process).
@MainActor enum RunControl {
    static var stop: () -> Void = {}
    static var answer: (Bool) -> Void = { _ in }
}

struct StopRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop task"

    func perform() async throws -> some IntentResult {
        await MainActor.run { RunControl.stop() }
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
