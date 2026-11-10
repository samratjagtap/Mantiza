import Foundation
import Network

/// Whether the phone has internet right now (for clear error messages: "no internet" instead of
/// "the request timed out").
enum Net {
    private static let monitor = NWPathMonitor()
    nonisolated(unsafe) private(set) static var online = true
    /// Size and time of the last AI request, for the task report (where does the time go?).
    @MainActor static var lastCall = ""

    static func start() {
        monitor.pathUpdateHandler = { path in online = path.status == .satisfied }
        monitor.start(queue: DispatchQueue(label: "mantiza.net"))
    }
}
