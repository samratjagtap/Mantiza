import Foundation
import MetricKit

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Crash, hang and CPU/disk diagnostics from iOS (MetricKit), kept on the phone in Documents/diagnostics/.
/// iOS hands them over at a later launch (up to a day later); nothing is sent anywhere.
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReports()
    static let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("diagnostics", isDirectory: true)

    func start() { MXMetricManager.shared.add(self) }

    /// Reports kept so far, newest first.
    static var files: [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Called by MetricKit on a background queue; Log is safe there (it locks, it is not main-actor bound).
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        for p in payloads {
            let counts: [(String, Int)] = [("crash", p.crashDiagnostics?.count ?? 0), ("hang", p.hangDiagnostics?.count ?? 0),
                                           ("cpu", p.cpuExceptionDiagnostics?.count ?? 0),
                                           ("disk", p.diskWriteExceptionDiagnostics?.count ?? 0)]
            let kinds = counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
            let name = "\(Int(p.timeStampEnd.timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
            try? p.jsonRepresentation().write(to: Self.dir.appendingPathComponent(name))
            Log.event("diagnostics", ["kinds": kinds.isEmpty ? "report" : kinds.joined(separator: ", "), "file": name])
        }
    }
}
