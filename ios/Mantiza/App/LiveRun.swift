import ActivityKit
import Foundation
import UserNotifications

/// The running task's Live Activity, and the approval notification for when the phone is in another app.
@MainActor final class LiveRun {
    private var activity: Activity<RunAttributes>?
    private var state = RunAttributes.ContentState(step: 0, total: 0, action: "Starting")

    func start(goal: String, runID: String) {
        end(nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        state = .init(step: 0, total: 0, action: "Starting")
        activity = try? Activity.request(attributes: RunAttributes(goal: String(goal.prefix(60)), runID: runID),
                                         content: .init(state: state, staleDate: nil))
    }

    func progress(step: Int, total: Int, action: String) {
        state.step = step
        state.total = total
        state.action = action
        push()
    }

    /// End activities a previous launch left behind (their run is gone; their buttons would do nothing).
    static func endStale() {
        for a in Activity<RunAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func paused(_ on: Bool) {
        state.paused = on
        state.action = on ? "Paused. A on the stick or Resume to go on." : "Going on…"
        push()
    }

    /// Replace the action line (recovery stages, "back online").
    func note(_ text: String) {
        state.action = text
        push()
    }

    func ask(_ question: String) {
        state.question = question
        push()
        Notifier.ask(question)
    }

    func answered() {
        state.question = nil
        push()
        Notifier.clearApproval()
    }

    func end(_ result: String?) {
        guard let a = activity else { return }
        activity = nil
        state.result = result ?? "Ended"
        state.question = nil
        let final = state
        Task { await a.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now + 30)) }
    }

    private func push() {
        guard let a = activity else { return }
        let s = state
        Task { await a.update(.init(state: s, staleDate: nil)) }
    }
}

/// Approval notification with Approve / Cancel actions (shown when Mantiza is in the background).
enum Notifier {
    static let category = "approval"
    static let approveAction = "approve"
    static let id = "approval"

    static func setUp(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let approve = UNNotificationAction(identifier: approveAction, title: "Approve", options: [.authenticationRequired])
        let cancel = UNNotificationAction(identifier: "cancel", title: "Cancel", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [approve, cancel], intentIdentifiers: [])])
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func ask(_ question: String) {
        let content = UNMutableNotificationContent()
        content.title = "Mantiza needs your OK"
        content.body = question
        content.sound = .default
        content.categoryIdentifier = category
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// A plain message (no actions).
    static func tell(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Mantiza"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static func clearApproval() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
