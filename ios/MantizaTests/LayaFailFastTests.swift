import Network
import XCTest
@testable import Mantiza

/// An unreachable quick picker costs one short wait, then steps aside so the big brain decides at once.
final class LayaFailFastTests: XCTestCase {
    private var saved: URLSession!
    private let laya = SystemOnePicker(service: .laya(URL(string: "http://mac.local:8765")!), key: "k")
    private let context = DecisionContext(subtask: Subtask(goal: "x", verification: ["y"]),
                                          reading: ScreenReading(frameID: 1, elements: []), jpeg: nil, history: [])

    override func setUp() {
        saved = HTTP.session
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        HTTP.session = URLSession(configuration: config)
        StubProtocol.queue = []
        StubProtocol.bodies = []
        Reachability.reset("laya")
    }

    override func tearDown() {
        HTTP.session = saved
        Reachability.reset("laya")
    }

    func testLayaHasAShortTimeout() {
        XCTAssertLessThanOrEqual(SystemOnePicker.Service.laya(URL(string: "http://m:1")!).timeout, 3)
    }

    func testTimeoutIsNotRetriedAndLayaIsSkippedAfterwards() async throws {
        StubProtocol.queue = [.failure(URLError(.timedOut)), .success((200, ["answers": [:]]))]
        let first = try await laya.decide(context)
        XCTAssertNil(first)
        XCTAssertEqual(StubProtocol.queue.count, 1, "no second attempt")
        XCTAssertTrue(Reachability.skipping("laya"))
        let second = try await laya.decide(context)
        XCTAssertNil(second)
        XCTAssertEqual(StubProtocol.queue.count, 1, "skipped without a request")
    }

    func testSkipEndsAfterTheWindowAndSuccessClearsIt() async throws {
        Reachability.down("laya", "test")
        XCTAssertFalse(Reachability.skipping("laya", now: Date().addingTimeInterval(Reachability.skip + 1)))
        Reachability.reset("laya")
        StubProtocol.queue = [.success((200, ["answers": [:]]))]
        _ = try await laya.decide(context)
        XCTAssertFalse(Reachability.isDown("laya"))
    }

    func testNetworkRetryCanBeTurnedOff() async {
        StubProtocol.queue = [.failure(URLError(.timedOut)), .success((200, ["ok": true]))]
        do {
            _ = try await HTTP.postJSON(URL(string: "https://example.invalid/x")!, headers: [:], body: [:], timeout: 5,
                                        networkRetry: false, service: "Test")
            XCTFail("expected the timeout")
        } catch {
            XCTAssertEqual(StubProtocol.queue.count, 1)
        }
    }

    func testFinderReadsTheAdvertisedAddress() {
        var txt = NWTXTRecord()
        txt["host"] = "Azads-Mac.local"
        txt["port"] = "8765"
        XCTAssertEqual(LayaFinder.url(txt), "http://Azads-Mac.local:8765")
        XCTAssertNil(LayaFinder.url(NWTXTRecord()))
    }
}
