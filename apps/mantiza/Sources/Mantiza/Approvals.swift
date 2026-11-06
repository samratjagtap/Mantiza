import Foundation
import UserNotifications

/// Asks the user before anything that can't be undone (send, pay, delete…). The question appears
/// as a notification with Approve / Don't buttons, so it works while another app is in front
/// (long-press or pull down the banner to see the buttons). It also shows in the Task tab.
/// No answer within a minute counts as "don't". Later: also on the device screen (buttons A/B).
@MainActor
final class Approvals: NSObject, ObservableObject {
    @Published var question: String?

    private var waiting: CheckedContinuation<Bool, Never>?
    private var waitingID: String?
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        let approve = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [])
        let deny = UNNotificationAction(identifier: "DENY", title: "Don't", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: "MANTIZA_APPROVAL",
                                                                 actions: [approve, deny], intentIdentifiers: [])])
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

    /// Answers the open question (from the notification or the Task tab).
    func answer(_ approved: Bool) {
        if let id = waitingID { center.removeDeliveredNotifications(withIdentifiers: [id]) }
        question = nil
        waitingID = nil
        waiting?.resume(returning: approved)
        waiting = nil
    }
}

extension Approvals: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let approved = response.actionIdentifier == "APPROVE"
        let id = response.notification.request.identifier
        Task { @MainActor in
            if self.waitingID == id { self.answer(approved) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
