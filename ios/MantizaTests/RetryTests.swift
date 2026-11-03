import XCTest
@testable import Mantiza

/// Answers queued responses in order: (status, JSON body) or a URLError.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var queue: [Result<(Int, [String: Any]), URLError>] = []
    nonisolated(unsafe) static var bodies: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            Self.bodies.append((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        }
        switch Self.queue.removeFirst() {
        case let .failure(error): client?.urlProtocol(self, didFailWithError: error)
        case let .success((status, json)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class RetryTests: XCTestCase {
    private var saved: URLSession!

    override func setUp() {
        saved = HTTP.session
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        HTTP.session = URLSession(configuration: config)
        StubProtocol.queue = []
        StubProtocol.bodies = []
    }

    override func tearDown() { HTTP.session = saved }

    private func claudeReply(_ text: String, stop: String = "end_turn") -> [String: Any] {
        ["stop_reason": stop, "content": [["type": "text", "text": text]], "model": "claude-opus-5-5"]
    }

    func testTimedOutRequestIsTriedOnceMore() async throws {
        StubProtocol.queue = [.failure(URLError(.timedOut)), .success((200, ["ok": true]))]
        let json = try await HTTP.postJSON(URL(string: "https://example.invalid/x")!, headers: [:], body: [:], timeout: 5, service: "Test")
        XCTAssertEqual(json["ok"] as? Bool, true)
    }

    func testCutOffAnswerIsAskedAgainWithMoreRoom() async throws {
        StubProtocol.queue = [.success((200, claudeReply("{\"done\":", stop: "max_tokens"))),
                              .success((200, claudeReply("{\"done\": true, \"reason\": \"ok\"}")))]
        let brain = ClaudeBrain(key: "k")
        let s = Subtask(goal: "x", verification: ["y"])
        let verdict = try await brain.verify(s, reading: ScreenReading(frameID: 1, elements: []), jpeg: nil)
        XCTAssertTrue(verdict.done)
        XCTAssertEqual(StubProtocol.bodies.count, 2)
        XCTAssertEqual(StubProtocol.bodies[1]["max_tokens"] as? Int, 2 * (StubProtocol.bodies[0]["max_tokens"] as? Int ?? 0))
    }

    func testRefusalIsNotRetried() async {
        StubProtocol.queue = [.success((200, claudeReply("", stop: "refusal")))]
        do {
            _ = try await ClaudeBrain(key: "k").verify(Subtask(goal: "x", verification: ["y"]),
                                                       reading: ScreenReading(frameID: 1, elements: []), jpeg: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(StubProtocol.bodies.count, 1)
            XCTAssertFalse(AgentRunner.recoverable(error))
        }
    }
}

/// A brain that fails the first `failures` decisions, then answers from the script.
struct FlakyBrain: BigBrain, @unchecked Sendable {
    final class Count: @unchecked Sendable { var n = 0 }
    var name = "flaky"
    var plan: Subtask
    var failures: Int
    var count = Count()
    var decide: (DecisionContext) -> AgentAction
    func plan(_ request: String) async throws -> Subtask { plan }
    func decide(_ c: DecisionContext) async throws -> Decision {
        count.n += 1
        if count.n <= failures { throw AIError.notJSON }
        return Decision(action: decide(c), reason: "", confidence: 1, source: "flaky")
    }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) { (true, "ok") }
}

@MainActor final class RecoveryLoopTests: XCTestCase {
    func testRejectedAnswerGetsAFreshLook() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "Look", verification: ["x"], maxActions: 3)
        let brain = FlakyBrain(plan: plan, failures: 2) { _ in .done("seen") }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain))
        XCTAssertEqual(outcome, .done("ok"))
        XCTAssertEqual(brain.count.n, 3)
    }

    func testTooManyRejectedAnswersFail() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "Look", verification: ["x"], maxActions: 3)
        let brain = FlakyBrain(plan: plan, failures: 10) { _ in .done("seen") }
        let outcome = await AgentRunner().run(plan, deps: phone.deps(brain))
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(brain.count.n, AgentRunner.maxRejected + 1)
    }

    func testRepeatedTapIsNudgedOnceThenStops() async {
        let phone = FakePhone()
        let brain = ScriptedBrain(plan: Subtask(goal: "x", verification: ["y"])) { c in
            let t = c.reading.find("Settings").first!
            return .tap(element: t.id, at: t.center)
        }
        let runner = AgentRunner()
        let outcome = await runner.run(brain.plan, deps: phone.deps(brain))
        guard case let .blocked(why) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(why.contains("same tap"), why)
        XCTAssertTrue(runner.steps.contains { $0.text.contains("asked for a different action") })
        XCTAssertEqual(phone.taps.count, 1)
    }
}

/// A screen whose last frame is old but which the system says is still current (or not).
@MainActor final class IdleScreen: ScreenSource {
    var latest: Frame?
    var live = true
    var confirmedAt: Date?
    func start() async throws {}
    func stop() async {}
}

@MainActor final class FreshnessTests: XCTestCase {
    func testStillSignalAnswersAtOnce() async throws {
        let screen = IdleScreen()
        screen.latest = Frame(image: DemoScreen.settings(), id: 1, capturedAt: Date().addingTimeInterval(-10))
        screen.confirmedAt = Date()
        let started = Date()
        _ = try await screen.frame(after: Date().addingTimeInterval(-1), timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    }

    func testWithoutStillSignalItWaits() async throws {
        let screen = IdleScreen()
        screen.latest = Frame(image: DemoScreen.settings(), id: 1, capturedAt: Date().addingTimeInterval(-10))
        let started = Date()
        _ = try await screen.frame(after: Date().addingTimeInterval(-1), timeout: 0.3)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.3)
    }

    func testIconTapIsDroppedWhenTheScreenMovedWhileDeciding() async {
        let phone = FakePhone()
        let plan = Subtask(goal: "Tap the icon", verification: ["x"], maxActions: 4)
        let brain = MovingBrain(plan: plan, screen: phone.screen)
        let runner = AgentRunner()
        let outcome = await runner.run(plan, deps: phone.deps(brain))
        XCTAssertEqual(outcome, .done("ok"))
        XCTAssertTrue(phone.taps.isEmpty)
        XCTAssertTrue(runner.steps.contains { $0.text.contains("screen moved while deciding") })
    }
}

/// Changes the screen while "thinking" about the first decision, then proposes an icon tap on the old screen.
struct MovingBrain: BigBrain, @unchecked Sendable {
    final class Count: @unchecked Sendable { var n = 0 }
    var name = "moving"
    var plan: Subtask
    let screen: StillScreen
    let count = Count()
    func plan(_ request: String) async throws -> Subtask { plan }
    func decide(_ c: DecisionContext) async throws -> Decision {
        count.n += 1
        if count.n == 1 {
            await MainActor.run { screen.show(DemoScreen.list(title: "Other", rows: ["A", "B"])) }
            return Decision(action: .tap(element: nil, at: CGPoint(x: 0.5, y: 0.5)), reason: "", confidence: 1, source: "moving")
        }
        return Decision(action: .done("ok"), reason: "", confidence: 1, source: "moving")
    }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) { (true, "ok") }
}
