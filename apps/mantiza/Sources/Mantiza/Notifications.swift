import UserNotifications

/// A tap on one of Mantiza's notifications (an approval, a choice, a schedule).
struct NoteReply: Sendable {
    let id: String
    let action: String
    let category: String
    let prompt: String?
}

/// One place that hears notification taps for the whole app. It becomes iOS's notification
/// delegate as the app starts, before any screen, so a tap that launched Mantiza isn't lost; a tap
/// that comes before its handler exists waits until the handler is added. It also keeps the
/// notification button sets together (setting one set used to drop the others).
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    private var handlers: [(NoteReply) -> Bool] = []
    private var waiting: [NoteReply] = []
    private var categories: [String: UNNotificationCategory] = [:]

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Adds a handler: it returns true when the tap is its own. Taps that waited are offered to it.
    func handle(_ handler: @escaping (NoteReply) -> Bool) {
        handlers.append(handler)
        waiting = waiting.filter { !handler($0) }
    }

    /// Registers (or replaces) a set of notification buttons, keeping all the others.
    func register(_ category: UNNotificationCategory) {
        categories[category.identifier] = category
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories.values))
    }

    private func deliver(_ reply: NoteReply) {
        if !handlers.contains(where: { $0(reply) }) {
            waiting.append(reply)
            if waiting.count > 10 { waiting.removeFirst() }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let reply = NoteReply(id: request.identifier, action: response.actionIdentifier,
                              category: request.content.categoryIdentifier,
                              prompt: request.content.userInfo["prompt"] as? String)
        Task { @MainActor in self.deliver(reply) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
