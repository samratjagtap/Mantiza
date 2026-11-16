import Foundation
import Network

/// The phone's internet, as the AI calls experience it: whether there is any, and whether it is
/// weak right now. Weak internet gets its own way of working (lighter pictures, one brain per step,
/// more patience per call, an early and clear stop) instead of the same calls timing out.
enum Net {
    private static let monitor = NWPathMonitor()
    private static let lock = NSLock()
    nonisolated(unsafe) private(set) static var online = true
    nonisolated(unsafe) private static var lowData = false   // the user's Low Data Mode
    nonisolated(unsafe) private static var cellular = false
    nonisolated(unsafe) private static var recent: [Double] = []  // seconds of the last AI calls; a failed one counts as 10
    /// Size and time of the last AI request, for the task report (where does the time go?).
    @MainActor static var lastCall = ""

    static func start() {
        monitor.pathUpdateHandler = { path in
            lock.lock()
            online = path.status == .satisfied
            lowData = path.isConstrained
            let nowCellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            if nowCellular != cellular { recent = [] }  // a new network: forget how the old one did
            cellular = nowCellular
            lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "mantiza.net"))
    }

    /// Every AI call reports how long it took (10 for one that failed).
    static func record(_ seconds: Double) {
        lock.lock()
        recent.append(seconds)
        if recent.count > 4 { recent.removeFirst() }
        lock.unlock()
    }

    /// Weak right now: Low Data Mode is on, or at least 2 of the last 3 AI calls took over 3.5 s
    /// (they normally take 0.5-2 s). It ends by itself when calls are quick again.
    static var weak: Bool {
        lock.lock(); defer { lock.unlock() }
        return lowData || recent.suffix(3).filter { $0 > 3.5 }.count >= 2
    }

    /// "mobile data, last AI calls 4.2 s, 6.0 s" for messages and the log.
    static var summary: String {
        lock.lock(); defer { lock.unlock() }
        var parts = [cellular ? "mobile data" : "Wi-Fi"]
        if lowData { parts.append("Low Data Mode") }
        if !recent.isEmpty {
            parts.append("last AI calls " + recent.suffix(3).map { $0 >= 10 ? "no answer" : String(format: "%.1f s", $0) }.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}
