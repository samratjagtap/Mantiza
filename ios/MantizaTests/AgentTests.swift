import XCTest
@testable import Mantiza

/// A big brain that answers from a script.
struct ScriptedBrain: BigBrain, @unchecked Sendable {
    var name = "script"
    var plan: Subtask
    var decide: (DecisionContext) -> AgentAction
    var verdict = true
    func plan(_ request: String) async throws -> Subtask { plan }
    func decide(_ c: DecisionContext) async throws -> Decision { Decision(action: decide(c), reason: "", confidence: 1, source: "script") }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) {
        (verdict, verdict ? "General is open" : "not yet")
    }
}

/// A fake phone: tapping a row of the Settings list opens a page with that title.
@MainActor final class FakePhone {
    let board = MockBoard()
    let screen = StillScreen()
    var taps: [CGPoint] = []

    init() {
        screen.show(DemoScreen.settings())
        board.onCommand = { [weak self] c in
            guard let self, c.name == "tap", c.ints.count >= 2 else { return }
            let p = CGPoint(x: Double(c.ints[0]) / 32767, y: Double(c.ints[1]) / 32767)
            self.taps.append(p)
            let row = Int(floor(((p.y * 844) - 170) / 52))
            if DemoScreen.rows.indices.contains(row) {
                self.screen.show(DemoScreen.list(title: DemoScreen.rows[row], rows: ["About", "Software Update", "Storage"]))
            }
        }
    }

    func deps(_ brain: BigBrain, approve: Bool = true) -> AgentRunner.Deps {
        AgentRunner.Deps(hands: Hands(channel: board.commands), screen: screen, big: brain, fast: nil,
                         approve: { _ in approve }, shouldStop: { false }, openURL: { _ in true })
    }
}

@MainActor final class AgentTests: XCTestCase {
    func testOpensGeneralEndToEnd() async {
        let phone = FakePhone()
        let brain = ScriptedBrain(plan: Subtask(goal: "Open General", app: nil, verification: ["General page is open"])) { c in
            if c.reading.find("About").isEmpty, let g = c.reading.find("General").first { return .tap(element: g.id, at: g.center) }
            return .done("About is visible")
        }
        let runner = AgentRunner()
        let outcome = await runner.run("Open General settings", deps: phone.deps(brain))
        XCTAssertEqual(outcome, .done("General is open"))
        XCTAssertEqual(phone.taps.count, 1)
        XCTAssertEqual(phone.taps[0].y, 194.0 / 844, accuracy: 0.02)
        XCTAssertTrue(phone.board.sent.contains("park"))
    }

    func testStuckScreenStops() async {
        let phone = FakePhone()
        // Tapping the title does nothing on the fake phone.
        let brain = ScriptedBrain(plan: Subtask(goal: "x", verification: ["y"])) { c in
            let t = c.reading.find("Settings").first!
            return .tap(element: t.id, at: t.center)
        }
        let outcome = await AgentRunner().run(brain.plan, deps: phone.deps(brain))
        guard case let .blocked(why) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(why.contains("same tap"), why)
    }

    func testRiskyTapNeedsApproval() async {
        let phone = FakePhone()
        phone.screen.show(DemoScreen.list(title: "Chat", rows: ["Send"]))
        let plan = Subtask(goal: "Send it", verification: ["sent"], allowedRisks: ["send"])
        let brain = ScriptedBrain(plan: plan) { c in
            let s = c.reading.find("Send").first!
            return .tap(element: s.id, at: s.center)
        }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain, approve: false))
        XCTAssertEqual(outcome, .blocked("You declined “Send”."))
        XCTAssertTrue(phone.taps.isEmpty)
    }

    func testHiddenRiskyButtonCannotBeTappedByCoordinates() async {
        let phone = FakePhone()
        phone.screen.show(DemoScreen.list(title: "Chat", rows: ["Delete"]))
        let plan = Subtask(goal: "Look", verification: ["x"])
        let brain = ScriptedBrain(plan: plan) { _ in .tap(element: nil, at: CGPoint(x: 32.0 / 390 + 0.03, y: 194.0 / 844)) }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain))
        guard case .blocked = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(phone.taps.isEmpty)
    }

    func testRefusesToTypeTextOutsideInputs() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "Type", inputs: ["hello"], verification: ["x"], maxActions: 2)
        let brain = ScriptedBrain(plan: plan) { _ in .type("rm -rf everything") }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain))
        guard case .blocked = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(phone.board.sent.contains { $0.hasPrefix("type") })
    }
}

final class SpotlightTests: XCTestCase {
    func testPicksTopMostResultNotSearchField() {
        let r = ScreenReading(frameID: 1, elements: [
            ScreenElement(id: 1, text: "Settings", box: CGRect(x: 0.2, y: 0.92, width: 0.2, height: 0.02)),
            ScreenElement(id: 2, text: "System Settings", box: CGRect(x: 0.2, y: 0.13, width: 0.3, height: 0.02)),
            ScreenElement(id: 3, text: "Settings", box: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.02)),
        ])
        XCTAssertEqual(AppLauncher.spotlightHit("Settings", in: r)?.id, 3)
        XCTAssertEqual(AppLauncher.spotlightHit("system", in: r)?.id, 2)
        XCTAssertNil(AppLauncher.spotlightHit("Maps", in: r))
    }

    func testIconLabelsIncludingTruncated() {
        let r = ScreenReading(frameID: 1, elements: [
            ScreenElement(id: 1, text: "Google Ma...", box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.02)),
            ScreenElement(id: 2, text: "Notes", box: CGRect(x: 0.1, y: 0.5, width: 0.1, height: 0.02)),
        ])
        XCTAssertEqual(AppLauncher.iconHit("Google Maps", in: r)?.id, 1)
        XCTAssertLessThan(AppLauncher.iconHit("notes", in: r)!.center.y, 0.5)
        XCTAssertNil(AppLauncher.iconHit("Go", in: r))
    }

    func testLastPageIsFoundByAppNamesNotClockPixels() {
        func page(_ texts: [String]) -> ScreenReading {
            ScreenReading(frameID: 1, elements: texts.enumerated().map {
                ScreenElement(id: $0.offset + 1, text: $0.element, box: CGRect(x: 0.1, y: 0.1 * Double($0.offset), width: 0.1, height: 0.02))
            })
        }
        // The same page a few seconds later: the time and clock numbers differ, the app names do not.
        XCTAssertEqual(AppLauncher.pageNames(page(["11:03", "10", "Weather", "Find My", "Q Search"])),
                       AppLauncher.pageNames(page(["11:04", "12", "Weather", "Find My", "Q Search"])))
        XCTAssertNotEqual(AppLauncher.pageNames(page(["Weather", "Notes"])), AppLauncher.pageNames(page(["Spotify", "Notes"])))
    }

    func testThirdPartyAppLinks() {
        XCTAssertEqual(AppLinks.url(for: "Uber Eats")?.absoluteString, "ubereats:")
        XCTAssertNil(AppLinks.url(for: "Some Unknown App"))
    }
}
