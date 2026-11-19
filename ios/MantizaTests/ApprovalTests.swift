import XCTest
@testable import Mantiza

@MainActor final class ApprovalTests: XCTestCase {
    func testFirstAnswerWinsAndOthersAreIgnored() async {
        let a = Approvals()
        var resolved: [(Bool, String)] = []
        a.onResolve = { resolved.append(($0, $1)) }
        a.onAsk = { _ in
            Task { @MainActor in
                a.resolve(true, source: "phone")
                a.resolve(false, source: "stick")  // too late: ignored
            }
        }
        let yes = await a.ask("Send?")
        XCTAssertTrue(yes)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.1, "phone")
        XCTAssertNil(a.question)
    }

    func testTimeoutMeansNo() async {
        let a = Approvals()
        var source = ""
        a.onResolve = { _, s in source = s }
        let yes = await a.ask("Delete?", timeout: 0.1)
        XCTAssertFalse(yes)
        XCTAssertEqual(source, "timeout")
    }

    func testStickPromptAnswerReachesApprovals() async {
        let board = MockBoard()
        board.askAnswer = "no"
        let a = Approvals()
        board.commands.onEvent = { e in
            if e == .yes { a.resolve(true, source: "stick") }
            if e == .no { a.resolve(false, source: "stick") }
        }
        a.onAsk = { q in Task { try? await board.commands.send(.prompt(seconds: 60, text: q)) } }
        let yes = await a.ask("Buy?")
        XCTAssertFalse(yes)
        XCTAssertEqual(board.sent, ["prompt 60 Buy?"])
        XCTAssertEqual(BoardCommand.unprompt("Answered on phone").line, "unprompt Answered on phone")
    }
}
