import XCTest
@testable import Mantiza

/// Counts how often the big brain is asked to decide.
final class CountingBrain: BigBrain, @unchecked Sendable {
    var name = "claude test"
    var decides = 0
    let plan: Subtask
    init(plan: Subtask) { self.plan = plan }
    func plan(_ request: String) async throws -> Subtask { plan }
    func decide(_ c: DecisionContext) async throws -> Decision {
        decides += 1
        if c.reading.find("About").isEmpty, let g = c.reading.find("General").first {
            return Decision(action: .tap(element: g.id, at: g.center), reason: "", confidence: 1, source: "claude")
        }
        return Decision(action: .done("About visible"), reason: "", confidence: 1, source: "claude")
    }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) {
        (!reading.find("About").isEmpty, "About visible")
    }
}

@MainActor final class WorkflowTests: XCTestCase {
    func testReplayUsesFewerAICallsThanFirstRun() async throws {
        let plan = Subtask(goal: "Open General", verification: ["About is visible"])
        // First run, decided by the AI.
        let phone1 = FakePhone(), brain1 = CountingBrain(plan: plan)
        let runner = AgentRunner()
        let first = await runner.run("Open General", deps: phone1.deps(brain1))
        guard case .done = first else { return XCTFail("\(first)") }
        let record = RunRecord(request: "Open General", plan: runner.subtask, steps: runner.steps, outcome: first.summary,
                               success: true, bigBrain: brain1.name)
        let w = try XCTUnwrap(Workflow(from: record))
        XCTAssertEqual(w.steps.map(\.kind), ["tap"])
        XCTAssertEqual(w.steps.first?.target, "General")

        // Replay on a fresh phone: no decide calls, same result.
        let phone2 = FakePhone(), brain2 = CountingBrain(plan: plan)
        let again = await AgentRunner().replay(w, deps: phone2.deps(brain2))
        guard case .done = again else { return XCTFail("\(again)") }
        XCTAssertGreaterThan(brain1.decides, 0)
        XCTAssertEqual(brain2.decides, 0)
        XCTAssertEqual(phone2.taps.count, 1)
    }

    func testReplayFallsBackToAIWhenScreenDiffers() async {
        let plan = Subtask(goal: "Open General", verification: ["About is visible"])
        let w = Workflow(id: UUID(), name: "x", request: "x", subtask: plan,
                         steps: [RecordedAction(kind: "tap", target: "Bluetooth Tethering", point: CGPoint(x: 0.2, y: 0.2))])
        let phone = FakePhone(), brain = CountingBrain(plan: plan)
        let outcome = await AgentRunner().replay(w, deps: phone.deps(brain))
        guard case .done = outcome else { return XCTFail("\(outcome)") }
        XCTAssertGreaterThan(brain.decides, 0)
    }

    func testFailedRunsAreNotSaved() {
        let r = RunRecord(request: "x", plan: Subtask(goal: "x"), steps: [], outcome: "no", success: false, bigBrain: "c")
        XCTAssertNil(Workflow(from: r))
    }

    func testSuggestionsFollowTimeOfDayAndRecency() throws {
        let cal = Calendar.current
        let morning = try XCTUnwrap(cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date()))
        let evening = try XCTUnwrap(cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date()))
        var coffee = Workflow(id: UUID(), name: "Order coffee", request: "c", subtask: Subtask(goal: "c"), steps: [])
        coffee.uses = (1...5).compactMap { cal.date(byAdding: .day, value: -$0, to: morning) }
        var music = Workflow(id: UUID(), name: "Play music", request: "m", subtask: Subtask(goal: "m"), steps: [])
        music.uses = (1...5).compactMap { cal.date(byAdding: .day, value: -$0, to: evening) }
        XCTAssertGreaterThan(WorkflowStore.score(coffee, now: morning), WorkflowStore.score(music, now: morning))
        XCTAssertGreaterThan(WorkflowStore.score(music, now: evening), WorkflowStore.score(coffee, now: evening))
        var old = coffee
        old.uses = (60...64).compactMap { cal.date(byAdding: .day, value: -$0, to: morning) }
        XCTAssertLessThan(WorkflowStore.score(old, now: morning), WorkflowStore.score(coffee, now: morning) / 10)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = WorkflowStore(file: file)
        store.add(coffee); store.add(music)
        XCTAssertEqual(store.suggestions(now: morning).first?.name, "Order coffee")
        XCTAssertEqual(WorkflowStore(file: file).workflows.count, 2)  // persisted
    }
}
