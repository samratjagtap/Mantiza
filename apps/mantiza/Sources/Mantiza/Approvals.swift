import Foundation
import UserNotifications

/// Asks the user before anything that can't be undone (send, pay, delete…). The question appears
/// as a notification with Approve / Don't buttons, so it works while another app is in front
/// (long-press or pull down the banner to see the buttons). It also shows in the Task tab.
/// No answer within a minute counts as "don't". Later: also on the device screen (buttons A/B).
@MainActor
final class Approvals: ObservableObject {
    @Published var question: String?
    /// When the open question is a choice ("Which Azad?"), its options; nil for yes/no.
    @Published var choices: [String]?

    private var waiting: CheckedContinuation<Bool, Never>?
    private var choosing: CheckedContinuation<Int?, Never>?
    private var waitingID: String?
    private let center = UNUserNotificationCenter.current()

    private var started = false

    func setUp() {
        guard !started else { return }
        started = true
        let approve = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [])
        let deny = UNNotificationAction(identifier: "DENY", title: "Don't", options: [.destructive])
        NotificationRouter.shared.register(UNNotificationCategory(identifier: "MANTIZA_APPROVAL", actions: [approve, deny],
                                                                  intentIdentifiers: []))
        // Taps on approval and choice notifications (stale ones are just dropped).
        NotificationRouter.shared.handle { [weak self] reply in
            guard reply.category == "MANTIZA_APPROVAL" || reply.category == "MANTIZA_CHOICE" else { return false }
            guard let self, self.waitingID == reply.id else { return true }
            if reply.action.hasPrefix("PICK_") {
                self.pick(Int(reply.action.dropFirst(5)))
            } else {
                self.answer(reply.action == "APPROVE")
            }
            return true
        }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Waits for the user's answer. True = approved.
    func ask(_ text: String, timeout: Double = 60) async -> Bool {
        answer(false)  // only one question at a time
        let id = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "Mantiza needs your OK"
        content.body = text
        content.sound = .default
        content.categoryIdentifier = "MANTIZA_APPROVAL"
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        question = text
        waitingID = id
        return await withCheckedContinuation { continuation in
            waiting = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if waitingID == id { answer(false) }
            }
        }
    }

    /// Asks the user to pick one option ("Which Azad?"). Nil = no answer within the time, or none.
    /// It is a question about what the user meant, not an approval: asked only when the request
    /// could mean several things.
    func choose(_ text: String, options: [String], timeout: Double = 60) async -> Int? {
        answer(false)
        let shown = Array(options.prefix(6))
        let actions = shown.enumerated().map { UNNotificationAction(identifier: "PICK_\($0.offset)", title: $0.element, options: []) }
            + [UNNotificationAction(identifier: "PICK_NONE", title: "None of these", options: [.destructive])]
        let choice = UNNotificationCategory(identifier: "MANTIZA_CHOICE", actions: actions, intentIdentifiers: [])
        NotificationRouter.shared.register(choice)
        let id = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "Mantiza: which one?"
        content.body = text + " (long-press to choose)"
        content.sound = .default
        content.categoryIdentifier = "MANTIZA_CHOICE"
        try? await Task.sleep(for: .milliseconds(300))  // let iOS register the new buttons first
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        question = text
        choices = shown
        waitingID = id
        return await withCheckedContinuation { continuation in
            choosing = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if waitingID == id { pick(nil) }
            }
        }
    }

    /// Answers the open choice (from the notification or the Task tab).
    func pick(_ index: Int?) {
        if let id = waitingID { center.removeDeliveredNotifications(withIdentifiers: [id]) }
        question = nil
        choices = nil
        waitingID = nil
        choosing?.resume(returning: index)
        choosing = nil
    }

    /// Answers the open question (from the notification or the Task tab).
    func answer(_ approved: Bool) {
        if choosing != nil { pick(nil); return }
        if let id = waitingID { center.removeDeliveredNotifications(withIdentifiers: [id]) }
        question = nil
        waitingID = nil
        waiting?.resume(returning: approved)
        waiting = nil
    }
}
