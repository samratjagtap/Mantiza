import CoreBluetooth
import Foundation

// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo fork, MIT); see THIRD_PARTY_NOTICES.md.

/// GATT layout of the Mantiza Hands command service (firmware/mantiza-hands/ble_link.h).
enum BoardUUID {
    static func make(_ short: String) -> CBUUID { CBUUID(string: "f5da\(short)-6c5e-4c62-bbd9-ba1b370af73d") }
    static let service = make("0600")
    static let cmd = make("0601")
    static let reply = make("0602")
    static let status = make("0603")
    /// Push-to-talk packets (firmware 0.4.0) in their own service; older sticks lack both.
    static let audioService = make("0605")
    static let audio = make("0604")
    static let all = [cmd, reply, status]
}

/// The JSON the board notifies on `status` every second (and answers to `status`).
struct BoardStatus: Codable, Equatable {
    struct BLE: Codable, Equatable { var mtu: Int?, phy: Int?, rdrop: Int?, hdrop: Int?, n: Int? }
    var fw: String?
    var up: Int?
    var rst: String?
    var heap: Int?
    var hid: String?
    var hgen: UInt32?
    var batt: Int?
    var chg: Bool?
    var pair: Bool?
    var stop: Int?
    /// Session auth (firmware 0.3.0): none (no secret yet) | locked | ok.
    var auth: String?
    var ble: BLE?

    /// The phone subscribed to the HID reports: the pointer and keyboard work.
    var inputReady: Bool { hid == "ok" }
    var battery: Int? { batt.flatMap { $0 >= 0 ? $0 : nil } }

    static func decode(_ data: Data) -> BoardStatus? { try? JSONDecoder().decode(BoardStatus.self, from: data) }
    static func decode(_ text: String) -> BoardStatus? { decode(Data(text.utf8)) }

    /// A notify may be cut short on a small MTU; keep older values for missing fields.
    func merged(with newer: BoardStatus) -> BoardStatus {
        var r = newer
        r.fw = newer.fw ?? fw; r.up = newer.up ?? up; r.rst = newer.rst ?? rst; r.heap = newer.heap ?? heap
        r.hid = newer.hid ?? hid; r.hgen = newer.hgen ?? hgen; r.batt = newer.batt ?? batt; r.chg = newer.chg ?? chg
        r.pair = newer.pair ?? pair; r.stop = newer.stop ?? stop; r.auth = newer.auth ?? auth
        let a = ble ?? BLE(), b = newer.ble ?? BLE()
        r.ble = BLE(mtu: b.mtu ?? a.mtu, phy: b.phy ?? a.phy, rdrop: b.rdrop ?? a.rdrop, hdrop: b.hdrop ?? a.hdrop,
                    n: b.n ?? a.n)
        return r
    }
}

/// One line on `reply`: an answer `<id> ok [extra]` / `<id> err <reason>`, or a device event `evt <name>`.
enum BoardLine: Equatable {
    case reply(BoardReply)
    case event(BoardEvent)

    static func parse(_ line: String) -> BoardLine? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("evt ") { return BoardEvent(String(text.dropFirst(4))).map { .event($0) } }
        return BoardReply.parse(text).map { .reply($0) }
    }
}

struct BoardReply: Equatable {
    let id: Int
    let ok: Bool
    let text: String  // extra after "ok", or the error reason

    static func parse(_ line: String) -> BoardReply? {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 2)
            .map(String.init)
        guard parts.count >= 2, let id = Int(parts[0]), parts[1] == "ok" || parts[1] == "err" else { return nil }
        return BoardReply(id: id, ok: parts[1] == "ok", text: parts.count > 2 ? parts[2] : "")
    }
}

/// Buttons and the shake sensor on the stick.
enum BoardEvent: Equatable {
    case a          // button A on the idle screen: run the suggested workflow
    case b          // button B on the idle screen
    case stop       // B held, or shaken while working: emergency stop
    case pairing    // pairing window opened on the stick
    case yes, no, timeout  // answer to a `prompt`
    case talkStart(UInt32)            // A held: recording utterance N, packets follow on `audio`
    case talkEnd(UInt32, packets: Int)
    case talkShort(UInt32)            // let go too soon to be speech

    init?(_ text: String) {
        let parts = text.split(separator: " ").map(String.init)
        let utt = parts.count > 1 ? UInt32(parts[1]) : nil
        switch parts.first {
        case "a": self = .a
        case "b": self = .b
        case "stop": self = .stop
        case "pairing": self = .pairing
        case "yes": self = .yes
        case "no": self = .no
        case "timeout": self = .timeout
        case "talk_start": guard let utt else { return nil }; self = .talkStart(utt)
        case "talk_short": guard let utt else { return nil }; self = .talkShort(utt)
        case "talk_end":
            guard let utt, parts.count > 2, let n = Int(parts[2]) else { return nil }
            self = .talkEnd(utt, packets: n)
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .a: return "a"
        case .b: return "b"
        case .stop: return "stop"
        case .pairing: return "pairing"
        case .yes: return "yes"
        case .no: return "no"
        case .timeout: return "timeout"
        case let .talkStart(u): return "talk_start \(u)"
        case let .talkEnd(u, n): return "talk_end \(u) \(n)"
        case let .talkShort(u): return "talk_short \(u)"
        }
    }
}

/// Commands in the firmware's vocabulary (mantiza-hands.ino). Pointer positions are 0...32767 per axis.
enum BoardCommand {
    static let unitMax = 32767

    case ping, status, version, home, park, keyboardToggle
    case at(Int, Int)
    case tap(Int, Int, holdMs: Int? = nil)
    case longPress(Int, Int, ms: Int)
    case stroke(Int, Int, Int, Int, steps: Int)
    case scroll(Int, Int)
    case type(String)
    case key(String)
    case ui(UiState, step: Int = 0, total: Int = 0, text: String)
    case next(String)
    case ask(seconds: Int, text: String)
    /// Non-blocking ask (firmware 0.2.0): answers at once, the choice follows as event yes / no / timeout.
    case prompt(seconds: Int, text: String)
    case unprompt(String)
    case pair, unpair
    case hello
    case auth(String)
    case secret(String)
    /// Send packet SEQ of utterance UTT on `audio` again.
    case audio(utterance: UInt32, seq: Int)

    enum UiState: String { case idle, run, done, error, info }

    var line: String {
        switch self {
        case .ping: return "ping"
        case .status: return "status"
        case .version: return "version"
        case .home: return "home"
        case .park: return "park"
        case .keyboardToggle: return "consumer keyboard"
        case let .at(x, y): return "at \(Self.clamp(x)) \(Self.clamp(y))"
        case let .tap(x, y, hold): return "tap \(Self.clamp(x)) \(Self.clamp(y))" + (hold.map { " \($0)" } ?? "")
        case let .longPress(x, y, ms): return "longpress \(Self.clamp(x)) \(Self.clamp(y)) \(ms)"
        case let .stroke(x1, y1, x2, y2, n):
            return "stroke \(Self.clamp(x1)) \(Self.clamp(y1)) \(Self.clamp(x2)) \(Self.clamp(y2)) \(min(max(n, 2), 100))"
        case let .scroll(v, h): return "scroll \(v) \(h)"
        case let .type(text): return "type " + Self.oneLine(text)
        case let .key(combo): return "key \(combo)"
        case let .ui(state, step, total, text):
            return "ui \(state.rawValue)" + (total > 0 ? " \(step)/\(total)" : "") + (text.isEmpty ? "" : " " + Self.oneLine(text))
        case let .next(text): return "next " + Self.oneLine(text)
        case let .ask(seconds, text): return "ask \(min(max(seconds, 1), 120)) " + Self.oneLine(text)
        case let .prompt(seconds, text): return "prompt \(min(max(seconds, 1), 120)) " + Self.oneLine(text)
        case let .unprompt(text): return "unprompt " + Self.oneLine(text)
        case .hello: return "hello"
        case let .auth(mac): return "auth \(mac)"
        case let .secret(hex): return "secret \(hex)"
        case let .audio(u, seq): return "audio \(u) \(seq)"
        case .pair: return "pair"
        case .unpair: return "unpair"
        }
    }

    /// Commands that change something on the phone: after a timeout they may or may not have run.
    var acts: Bool {
        switch self {
        case .tap, .longPress, .stroke, .scroll, .type, .key, .home, .keyboardToggle: return true
        default: return false
        }
    }

    static func clamp(_ v: Int) -> Int { min(max(v, 0), unitMax) }
    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
