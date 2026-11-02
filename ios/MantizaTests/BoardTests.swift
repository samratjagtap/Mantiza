import XCTest
@testable import Mantiza

@MainActor final class BoardTests: XCTestCase {
    func testParsesRepliesAndEvents() {
        XCTAssertEqual(BoardLine.parse("12 ok"), .reply(BoardReply(id: 12, ok: true, text: "")))
        XCTAssertEqual(BoardLine.parse("7 err tap needs x y in 0..32767\n"),
                       .reply(BoardReply(id: 7, ok: false, text: "tap needs x y in 0..32767")))
        XCTAssertEqual(BoardLine.parse("evt stop"), .event(.stop))
        XCTAssertNil(BoardLine.parse("evt nonsense"))
        XCTAssertNil(BoardLine.parse("boot Mantiza Hands 7C3E"))
    }

    func testDecodesFirmwareStatus() throws {
        let json = #"{"fw":"0.1.0","up":1234,"rst":"power-on","heap":151000,"hid":"ok","hgen":3,"batt":82,"chg":false,"pair":false,"stop":0,"ble":{"mtu":247,"phy":2,"rdrop":0,"hdrop":0,"n":1}}"#
        let s = try XCTUnwrap(BoardStatus.decode(json))
        XCTAssertTrue(s.inputReady)
        XCTAssertEqual(s.battery, 82)
        XCTAssertEqual(s.ble?.mtu, 247)
        let partial = try XCTUnwrap(BoardStatus.decode(#"{"hid":"off"}"#))
        let merged = s.merged(with: partial)
        XCTAssertFalse(merged.inputReady)
        XCTAssertEqual(merged.fw, "0.1.0")
        XCTAssertEqual(BoardStatus.decode(#"{"batt":-1}"#)?.battery, nil)
    }

    func testCommandLines() {
        XCTAssertEqual(BoardCommand.tap(-5, 40000).line, "tap 0 32767")
        XCTAssertEqual(BoardCommand.stroke(1, 2, 3, 4, steps: 500).line, "stroke 1 2 3 4 100")
        XCTAssertEqual(BoardCommand.ui(.run, step: 2, total: 5, text: "Opening\nMessages").line, "ui run 2/5 Opening Messages")
        XCTAssertEqual(BoardCommand.ui(.idle, text: "").line, "ui idle")
        XCTAssertEqual(BoardCommand.ask(seconds: 500, text: "Send?").line, "ask 120 Send?")
        XCTAssertEqual(BoardCommand.keyboardToggle.line, "consumer keyboard")
        XCTAssertTrue(BoardCommand.type("x").acts)
        XCTAssertFalse(BoardCommand.status.acts)
    }

    func testTypeChunksNeverEndWithSpace() {
        XCTAssertEqual(Hands.chunks("hello world", size: 6), ["hello", " world"])
        XCTAssertEqual(Hands.chunks("hi  ", size: 10), ["hi", " ", " "])
        XCTAssertEqual(Hands.chunks("   x", size: 2), [" ", " ", " x"])
        let long = String(repeating: "ab ", count: 100)
        let parts = Hands.chunks(long, size: 50)
        XCTAssertEqual(parts.joined(), long)
        XCTAssertTrue(parts.allSatisfy { $0 == " " || ($0.last != " " && $0.count <= 50) })
    }

    func testChannelMatchesRepliesAndEvents() async throws {
        let board = MockBoard()
        var events: [BoardEvent] = []
        board.commands.onEvent = { events.append($0) }
        let text = try await board.commands.send(.status)
        XCTAssertEqual(BoardStatus.decode(text)?.fw, "mock")
        board.commands.handle("evt a")
        XCTAssertEqual(events, [.a])
        let answer = try await board.commands.send(.ask(seconds: 5, text: "Send?"))
        XCTAssertEqual(answer, "yes")
    }

    func testChannelFailsWhenDisconnected() async {
        let board = MockBoard()
        board.isConnected = false
        do {
            try await board.commands.send(.ping)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? BoardError)?.kind, .notConnected)
        }
    }

    func testRefusedCommandThrows() async {
        let board = FailingBoard()
        do {
            try await board.commands.send(.tap(1, 1))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? BoardError)?.kind, .refused)
        }
    }

    func testHandsTapsThenParks() async throws {
        let board = MockBoard()
        let hands = Hands(channel: board.commands)
        try await hands.tap(CGPoint(x: 0.5, y: 0.25))
        try await hands.type("Hi there ")
        XCTAssertEqual(board.sent, ["tap 16384 8192", "park", "type Hi there", "key space"])
        do { try await hands.type("नमस्ते"); XCTFail("non-ASCII must be refused") } catch {}
        XCTAssertEqual(board.sent.count, 4)
    }
}

/// Answers every command with an error.
@MainActor final class FailingBoard: BoardTransport {
    let commands = CommandChannel()
    var isConnected = true
    init() { commands.transport = self; commands.linkUp() }
    func write(_ line: String) throws {
        let id = BoardCommandLine(line).id
        Task { @MainActor in self.commands.handle("\(id) err mouse not ready") }
    }
}
