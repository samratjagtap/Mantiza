import Foundation
import os

/// App log. `event` lines are structured ("E2E {json}") so the Mac e2e harness (tools/e2e) can follow a run
/// from the device syslog; `info` lines are for people. Secrets registered with `redact` never reach either.
enum Log {
    static let subsystem = "com.azadjagtap.mantiza"
    private static let app = Logger(subsystem: subsystem, category: "app")
    private static let e2e = Logger(subsystem: subsystem, category: "e2e")
    nonisolated(unsafe) private static var secrets: [String] = []
    private static let lock = NSLock()
    /// The last lines, newest last, for the in-app log screen.
    nonisolated(unsafe) private(set) static var recent: [String] = []

    static func redact(_ values: [String]) {
        lock.lock(); secrets = values.filter { $0.count >= 8 }; lock.unlock()
    }

    static func clean(_ text: String) -> String {
        lock.lock(); let hidden = secrets; lock.unlock()
        return hidden.reduce(text) { $0.replacingOccurrences(of: $1, with: "‹redacted›") }
    }

    static func info(_ text: String) {
        let line = clean(text)
        app.log("\(line, privacy: .public)")
        remember(line)
    }

    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var body = fields
        body["evt"] = name
        body["t"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = clean(json)
        e2e.log("E2E \(line, privacy: .public)")
        remember("· " + line)
    }

    private static func remember(_ line: String) {
        lock.lock()
        recent.append(line)
        if recent.count > 300 { recent.removeFirst(recent.count - 300) }
        lock.unlock()
    }
}
