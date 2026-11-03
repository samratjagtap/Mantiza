import XCTest
@testable import Mantiza

/// Vectors from Python's hmac/hashlib, the same formulas as firmware/mantiza-hands/session_auth.cpp.
final class SessionAuthTests: XCTestCase {
    let secret = Data(0..<32)
    let nonce = Data(100..<116)

    func testMatchesReferenceVectors() {
        XCTAssertEqual(SessionAuth.answer(secret: secret, nonce: nonce),
                       "82b166a6ea164ce7bde4cb0bbec5b7e5a3db5c6f3eea49e9a83f36f46eb5d6db")
        XCTAssertEqual(SessionAuth.sign("123456 tap 100 200", secret: secret, nonce: nonce),
                       "123456 tap 100 200 ~d6c1709e2cdde7b4")
        XCTAssertEqual(SessionAuth.code(secret), "5357")
    }

    func testHexRoundTripAndBadInput() {
        XCTAssertEqual(SessionAuth.unhex(SessionAuth.hex(secret)), secret)
        XCTAssertNil(SessionAuth.unhex("abc"))
        XCTAssertNil(SessionAuth.unhex("zz"))
        XCTAssertEqual(SessionAuth.newSecret().count, 32)
    }

    @MainActor func testChannelSignsEveryLine() async throws {
        let board = MockBoard()
        board.commands.signer = { SessionAuth.sign($0, secret: self.secret, nonce: self.nonce) }
        try await board.commands.send(.ping)
        XCTAssertTrue(board.lines[0].contains(" ping ~"))
        XCTAssertEqual(BoardCommand.secret("ab").line, "secret ab")
        XCTAssertEqual(CommandChannel.timeout(.secret("ab")), 70)
    }
}
