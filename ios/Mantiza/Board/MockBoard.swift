import Foundation

/// A pretend stick: answers every command, so the app runs in the Simulator and in tests without hardware.
@MainActor final class MockBoard: BoardTransport {
    let commands = CommandChannel()
    private(set) var lines: [String] = []
    var isConnected = true
    /// Answer for `ask` (approval on the stick): "yes", "no" or "timeout".
    var askAnswer = "yes"
    /// Answer `prompt` with an event (false: leave it open, as if nobody pressed a button).
    var answersPrompts = true
    /// Called for every command after the reply is queued, e.g. to move a fake screen along in tests.
    var onCommand: ((BoardCommandLine) -> Void)?
    var replyDelay: Duration = .milliseconds(5)

    init() {
        commands.transport = self
        commands.linkUp()
    }

    var status: BoardStatus {
        BoardStatus(fw: "mock", up: 1000, rst: "power-on", heap: 100_000, hid: "ok", hgen: 1, batt: 87, chg: false,
                    pair: false, stop: 0, ble: .init(mtu: 247, phy: 2, rdrop: 0, hdrop: 0, n: 1))
    }

    /// Commands sent so far, without request ids.
    var sent: [String] { lines.map { BoardCommandLine($0).text } }

    func write(_ line: String) throws {
        guard isConnected else { throw BoardError.notConnected }
        lines.append(line)
        let command = BoardCommandLine(line)
        let reply: String
        switch command.name {
        case "status": reply = "ok " + String(decoding: (try? JSONEncoder().encode(status)) ?? Data(), as: UTF8.self)
        case "version": reply = "ok mock"
        case "ask": reply = "ok " + askAnswer
        default: reply = "ok"
        }
        let delay = replyDelay, answer = askAnswer
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.commands.handle("\(command.id) \(reply)")
            self?.onCommand?(command)
            if command.name == "prompt", self?.answersPrompts == true {
                try? await Task.sleep(for: delay)
                self?.commands.handle("evt \(answer)")
            }
        }
    }
}

/// "<id> <name> <args...>" as written to the board.
struct BoardCommandLine: Equatable {
    let id: Int
    let name: String
    let args: [String]
    let text: String  // without the id

    init(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        id = Int(parts.first ?? "") ?? 0
        text = parts.count > 1 ? parts[1] : ""
        let words = text.split(separator: " ").map(String.init)
        name = words.first ?? ""
        args = Array(words.dropFirst())
    }

    var ints: [Int] { args.compactMap(Int.init) }
}
