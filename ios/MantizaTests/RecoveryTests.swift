import XCTest
@testable import Mantiza

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

@MainActor final class RecoveryTests: XCTestCase {
    private func link(stick: Bool = true, pointer: Bool = true, screen: Bool = true, frameAt: Double = 1000) -> Recovery.Link {
        Recovery.Link(stick: stick, pointer: pointer, screen: screen, frameAt: frameAt)
    }

    func testStagesAfterTheStickDrops() {
        var r = Recovery(at: 100)
        XCTAssertEqual(r.next(link(stick: false, pointer: false), at: 100), .wait(.init(part: .stick, ask: false)))
        XCTAssertEqual(r.next(link(pointer: false), at: 107), .wait(.init(part: .pointer, ask: false)))
        XCTAssertEqual(r.next(link(frameAt: 99), at: 110), .wait(.init(part: .screen, ask: false)),
                       "everything up, but nothing seen on screen since the loss")
        XCTAssertEqual(r.next(link(frameAt: 111), at: 111), .live)
    }

    func testAsksOnlyAfterEachPartsQuietTime() {
        var r = Recovery(at: 0)
        XCTAssertEqual(r.next(link(stick: false), at: 0), .wait(.init(part: .stick, ask: false)))
        XCTAssertEqual(r.next(link(stick: false), at: 29), .wait(.init(part: .stick, ask: false)))
        XCTAssertEqual(r.next(link(stick: false), at: 30), .wait(.init(part: .stick, ask: true)))
        XCTAssertEqual(r.next(link(screen: false), at: 31), .wait(.init(part: .screen, ask: false)), "a new part starts quiet")
        XCTAssertEqual(r.next(link(screen: false), at: 41), .wait(.init(part: .screen, ask: true)))
    }

    func testGivesUpAfterFiveMinutesNamingWhatIsMissing() {
        var r = Recovery(at: 0)
        _ = r.next(link(screen: false), at: 0)
        guard case let .giveUp(reason) = r.next(link(screen: false), at: 300) else { return XCTFail() }
        XCTAssertTrue(reason.contains("Screen sharing"))
    }

    func testRunPausesForALostStickAndGoesOn() async {
        let phone = FakePhone()
        let board = phone.board
        final class Calls: @unchecked Sendable { var n = 0 }
        let calls = Calls()
        let plan = Subtask(goal: "Open General", verification: ["General page is open"], maxActions: 5)
        let brain = ScriptedBrain(plan: plan) { c in
            calls.n += 1
            if c.reading.find("About").isEmpty, let g = c.reading.find("General").first { return .tap(element: g.id, at: g.center) }
            return .done("About is visible")
        }
        var deps = phone.deps(brain)
        var stages: [Recovery.Stage?] = []
        deps.link = { Recovery.Link(stick: board.isConnected, pointer: true, screen: true, frameAt: Date().timeIntervalSince1970) }
        deps.onRecover = { stages.append($0) }
        // The stick drops as the first step is announced (just before its tap) and comes back a moment later.
        let taps = board.onCommand
        var dropped = false
        board.onCommand = { c in
            taps?(c)
            guard c.name == "ui", !dropped else { return }
            dropped = true
            board.isConnected = false
            Task { try? await Task.sleep(for: .milliseconds(700)); board.isConnected = true }
        }
        let runner = AgentRunner()
        let outcome = await runner.run(plan, deps: deps)
        XCTAssertEqual(outcome, .done("General is open"))
        XCTAssertEqual(phone.taps.count, 1)
        XCTAssertEqual(stages.first??.part, .stick)
        XCTAssertNil(stages.last ?? nil, "cleared when live again")
        XCTAssertTrue(runner.steps.contains { $0.text.contains("connection back") })
    }

    func testWithoutALinkALostStickStillFails() async {
        let phone = FakePhone()
        phone.board.isConnected = false
        let plan = Subtask(goal: "Open General", verification: ["x"], maxActions: 3)
        let brain = ScriptedBrain(plan: plan) { c in
            let g = c.reading.find("General").first!
            return .tap(element: g.id, at: g.center)
        }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain))
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
    }
}
