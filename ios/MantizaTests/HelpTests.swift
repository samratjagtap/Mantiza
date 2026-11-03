import XCTest
@testable import Mantiza

@MainActor final class HelpTests: XCTestCase {
    /// Taps the (dead) title until the user has helped, then finishes.
    private func stubborn(_ plan: Subtask, finishAfterHelp: Bool) -> ScriptedBrain {
        ScriptedBrain(plan: plan) { c in
            if finishAfterHelp, c.history.contains(where: { $0.contains("fixed it by hand") }) { return .done("ok") }
            let t = c.reading.find("Settings").first!
            return .tap(element: t.id, at: t.center)
        }
    }

    func testStuckAsksTheUserAndGoesOn() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "x", verification: ["y"], maxActions: 10)
        var deps = phone.deps(stubborn(plan, finishAfterHelp: true))
        var asked: [String] = []
        deps.askHelp = { reason in asked.append(reason); return true }
        let outcome = await AgentRunner().run(plan, deps: deps)
        XCTAssertEqual(outcome, .done("General is open"))
        XCTAssertEqual(asked, ["The same tap did not work twice."])
    }

    func testAsksAtMostTwiceThenGivesUp() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "x", verification: ["y"], maxActions: 20)
        var deps = phone.deps(stubborn(plan, finishAfterHelp: false))
        var asked = 0
        deps.askHelp = { _ in asked += 1; return true }
        let outcome = await AgentRunner().run(plan, deps: deps)
        XCTAssertEqual(outcome, .blocked("The same tap did not work twice."))
        XCTAssertEqual(asked, AgentRunner.maxHelp)
    }

    func testDeclinedHelpStops() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "x", verification: ["y"], maxActions: 10)
        var deps = phone.deps(stubborn(plan, finishAfterHelp: true))
        deps.askHelp = { _ in false }
        let outcome = await AgentRunner().run(plan, deps: deps)
        XCTAssertEqual(outcome, .blocked("The same tap did not work twice."))
    }

    func testSpokenInstructionReachesTheNextDecision() async {
        let phone = FakePhone()
        let runner = AgentRunner()
        let plan = Subtask(goal: "x", verification: ["y"], maxActions: 6)
        let brain = AmendingBrain(plan: plan, runner: runner)
        let outcome = await runner.run(plan, deps: phone.deps(brain))
        XCTAssertEqual(outcome, .done("ok"))
        XCTAssertTrue(runner.steps.contains { $0.text == "you added: use Wi-Fi" })
    }

    func testPauseWaitsThenLooksAgain() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "x", verification: ["y"], maxActions: 3)
        let brain = ScriptedBrain(plan: plan) { _ in .done("ok") }
        var deps = phone.deps(brain)
        let until = Date().addingTimeInterval(0.6)
        deps.paused = { Date() < until }
        let runner = AgentRunner()
        let started = Date()
        let outcome = await runner.run(plan, deps: deps)
        XCTAssertEqual(outcome, .done("General is open"))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.5)
        XCTAssertTrue(runner.steps.contains { $0.text == "paused" })
        XCTAssertTrue(runner.steps.contains { $0.text == "resumed; looking again" })
    }
}

/// The user speaks an extra instruction while the first decision is being made; the next one must see it.
struct AmendingBrain: BigBrain, @unchecked Sendable {
    var name = "amending"
    var plan: Subtask
    let runner: AgentRunner
    func plan(_ request: String) async throws -> Subtask { plan }
    func decide(_ c: DecisionContext) async throws -> Decision {
        if c.history.contains("the user adds: use Wi-Fi") { return Decision(action: .done("ok"), reason: "", confidence: 1, source: "a") }
        await MainActor.run { runner.amend("use Wi-Fi") }
        return Decision(action: .wait, reason: "", confidence: 1, source: "a")
    }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) { (true, "ok") }
}
