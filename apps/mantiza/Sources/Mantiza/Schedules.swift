import Foundation
import MantizaKit
import UserNotifications

/// Tasks at set times ("every morning at 8, read my calendar").
///
/// iOS doesn't let an app start itself on a timer, so a schedule runs one of two ways:
/// - Reminder (no setup): at the time, a notification "Time for: …" with Run now; a tap runs it.
///   Works with the phone locked too.
/// - By itself: the user's own Shortcuts automation (Time of Day → Open URLs) opens Mantiza's
///   mantiza://run link at that time. Apps can't create automations, so the Schedules page shows
///   the steps and the link. Mantiza sends no notification for these.
@MainActor
final class Schedules: ObservableObject {
    static let shared = Schedules()

    struct Schedule: Codable, Identifiable, Hashable {
        var id = UUID()
        var prompt: String
        var hour: Int
        var minute: Int
        var days: [Int] = []          // Calendar weekdays, 1 = Sunday … 7 = Saturday; [] = every day
        var on = true
        var handsFree = false         // runs through the user's Shortcuts automation

        var link: URL { Shared.runURL(prompt) }
    }

    @Published private(set) var all: [Schedule] = []
    /// nil until checked; false when the user turned Mantiza's notifications off.
    @Published private(set) var notificationsAllowed: Bool?

    private let store = "schedules.v1"
    private let category = "MANTIZA_SCHEDULE"
    private var onRun: ((String) -> Void)?
    private var started = false

    init() {
        if let data = UserDefaults.standard.data(forKey: store),
           let saved = try? JSONDecoder().decode([Schedule].self, from: data) {
            all = saved
        }
    }

    /// Called once when the app starts: what to do when a schedule's notification is tapped.
    func start(onRun: @escaping (String) -> Void) {
        self.onRun = onRun
        guard !started else { return }
        started = true
        let run = UNNotificationAction(identifier: "RUN", title: "Run now", options: [.foreground])
        let skip = UNNotificationAction(identifier: "SKIP", title: "Skip", options: [])
        NotificationRouter.shared.register(UNNotificationCategory(identifier: category, actions: [run, skip], intentIdentifiers: []))
        NotificationRouter.shared.handle { [weak self] reply in
            guard let self, reply.category == self.category else { return false }
            if reply.action != "SKIP", reply.action != UNNotificationDismissActionIdentifier, let prompt = reply.prompt {
                self.onRun?(prompt)
            }
            return true
        }
        sync()
    }

    // MARK: - Changes

    /// Adds a schedule (or returns the same one if it already exists).
    @discardableResult
    func add(prompt: String, hour: Int, minute: Int, days: [Int]) -> Schedule {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = Schedules.normal(days)
        if let same = all.first(where: { Words.norm($0.prompt) == Words.norm(text) && $0.hour == hour && $0.minute == minute && $0.days == d }) {
            return same
        }
        let s = Schedule(prompt: text, hour: hour, minute: minute, days: d)
        all.append(s)
        all.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
        return s
    }

    func update(_ s: Schedule) {
        guard let i = all.firstIndex(where: { $0.id == s.id }) else { return }
        var t = s
        t.days = Schedules.normal(t.days)
        all[i] = t
        all.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: store) }
        sync()
    }

    // MARK: - Notifications

    /// Puts iOS's pending reminders in line with the list: one repeating reminder per day (or one
    /// daily) for each schedule that is on and runs as a reminder.
    func sync() {
        let center = UNUserNotificationCenter.current()
        let list = all
        let category = self.category
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("schedule.") }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            if list.contains(where: { $0.on && !$0.handsFree }) {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            for s in list where s.on && !s.handsFree {
                let content = UNMutableNotificationContent()
                content.title = "Time for: \(s.prompt)"
                content.body = "Tap to let Mantiza do it now."
                content.sound = .default
                content.categoryIdentifier = category
                content.threadIdentifier = "schedules"
                content.userInfo = ["prompt": s.prompt]
                for day in s.days.isEmpty ? [0] : s.days {
                    var when = DateComponents()
                    when.hour = s.hour
                    when.minute = s.minute
                    if day > 0 { when.weekday = day }
                    let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
                    try? await center.add(UNNotificationRequest(identifier: "schedule.\(s.id.uuidString).\(day)",
                                                                content: content, trigger: trigger))
                }
            }
            await refreshPermission()
        }
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            ? true : (settings.authorizationStatus == .notDetermined ? nil : false)
    }

    // MARK: - Words

    /// Days sorted and without repeats; all seven days means every day ([]).
    static func normal(_ days: [Int]) -> [Int] {
        let set = Set(days.filter { (1...7).contains($0) })
        return set.count == 7 ? [] : set.sorted()
    }

    /// "monday" → 2 (Calendar weekday).
    static func weekday(_ name: String) -> Int? {
        switch name.lowercased().prefix(3) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return nil
        }
    }

    /// "Every day", "Weekdays", "Weekends" or "Mon, Wed".
    static func describe(_ days: [Int]) -> String {
        let d = normal(days)
        if d.isEmpty { return "Every day" }
        if d == [2, 3, 4, 5, 6] { return "Weekdays" }
        if d == [1, 7] { return "Weekends" }
        let names = Calendar.current.shortWeekdaySymbols
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        return order.filter { d.contains($0) }.map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// "8:00 AM" in the phone's own style.
    static func time(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
