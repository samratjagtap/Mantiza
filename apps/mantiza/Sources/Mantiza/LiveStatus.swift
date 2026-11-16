import ActivityKit
import Foundation
import MantizaKit

/// Shows the running task as a Live Activity: on the Lock Screen, as a banner, and in the Dynamic
/// Island on iPhones that have one. While Mantiza works inside another app, this is where the user
/// sees what it is doing.
///
/// Practice followed here:
/// - It is started while Mantiza is in front (iOS only allows that), and updated from the app
///   itself while it runs in the background: no server, no push.
/// - Updates are held to one every 0.7 s: steps change faster than anyone reads, and iOS may
///   drop updates that come too often.
/// - Every update carries a "stale" time 3 minutes ahead, so if the app is ever killed mid-task
///   the Lock Screen shows it as out of date instead of "working" forever.
/// - When the task ends, the result stays for a minute (3 minutes after a failure), then goes.
@MainActor
final class LiveStatus {
    static let shared = LiveStatus()

    private var activity: Activity<TaskActivity>?
    private var waiting: TaskActivity.ContentState?
    private var sender: Task<Void, Never>?
    private var lastSent = Date.distantPast
    private let gap = 0.7

    func begin(request: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One at a time: an older one (a task that ended moments ago) makes way.
        for old in Activity<TaskActivity>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let state = TaskActivity.ContentState(status: "Planning…", phase: .working)
        activity = try? Activity.request(attributes: TaskActivity(request: request),
                                         content: content(state), pushType: nil)
        lastSent = Date()
    }

    func update(_ status: String) {
        guard activity != nil else { return }
        let phase: TaskActivity.Phase = status.hasPrefix("Waiting for your OK") || status.hasPrefix("Which") ? .asking : .working
        waiting = TaskActivity.ContentState(status: LiveStatus.short(status), phase: phase)
        guard sender == nil else { return }
        sender = Task { [weak self] in
            guard let self else { return }
            let wait = self.gap - Date().timeIntervalSince(self.lastSent)
            if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
            self.sender = nil
            guard let state = self.waiting, let activity = self.activity else { return }
            self.waiting = nil
            self.lastSent = Date()
            await activity.update(self.content(state))
        }
    }

    func finish(_ status: String) {
        guard let activity else { return }
        self.activity = nil
        sender?.cancel()
        sender = nil
        waiting = nil
        let ok = status.hasPrefix("✅") || status.hasPrefix("💬")
        let phase: TaskActivity.Phase = ok ? .done : (status.hasPrefix("⏹") ? .stopped : .failed)
        let state = TaskActivity.ContentState(status: LiveStatus.short(status), phase: phase)
        let stay: TimeInterval = ok ? 60 : (phase == .stopped ? 5 : 180)
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(stay)))
        }
    }

    private func content(_ state: TaskActivity.ContentState) -> ActivityContent<TaskActivity.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(180))
    }

    /// The status without its emoji mark (the widget draws its own) and held to a readable length.
    private static func short(_ status: String) -> String {
        var s = status
        for mark in ["✅", "❌", "⏹", "💬", "❓"] where s.hasPrefix(mark) { s = String(s.dropFirst(mark.count)) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.count > 140 ? String(s.prefix(139)) + "…" : s
    }
}
