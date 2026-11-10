import AlarmKit
import AVFoundation
import Contacts
import EventKit
import Foundation
import SwiftUI
import UIKit

/// One step of a plan. "action" says what kind; only the fields that action needs are set.
/// Direct actions go through iOS itself (no screen, no AI); "screen" is the AI loop that looks
/// at the screen and taps. Research behind each route: Docs/Mantiza Roadmap/ios-direct-actions-research.md
struct PlanStep: Codable {
    var action: String
    // who / what
    var contact: String?      // a name as the user said it, looked up in Contacts
    var phone: String?        // a number the user gave directly
    var email: String?
    var subject: String?
    var text: String?         // message, title, or text to type: copied from the request
    // when
    var time: String?         // "HH:mm", 24 h (alarm)
    var days: [String]?       // weekdays for a repeating alarm: "monday" … "sunday"
    var seconds: Int?         // timer length
    var start: String?        // "yyyy-MM-ddTHH:mm", local time (event start, reminder due)
    var end: String?          // event end
    // settings / keys
    var value: Double?        // brightness 0…1
    var on: Bool?             // flashlight
    var key: String?          // device key name
    var count: Int?
    // places
    var destination: String?
    var mode: String?         // driving, walking, transit, cycling
    var maps: String?         // "apple" or "google"
    // screen steps (the AI loop)
    var app: String?
    var goal: String?
    var success_text: String?
    var needs_approval: Bool?
    var max_steps: Int?
    var state: String?
    var state_value: Bool?
    var business: Bool?               // WhatsApp Business instead of WhatsApp (only when the user says so)
    var routine: String?              // the kind of screen task, for record-once replay
    var values: [String: String]?     // this task's values for the routine's {blanks}

    var subtask: Subtask {
        Subtask(app: app, goal: goal ?? "", text: text, success_text: success_text, needs_approval: needs_approval,
                max_steps: max_steps, state: state, state_value: state_value)
    }

    /// Short description for the log.
    var summary: String {
        var parts = [action]
        for v in [contact, phone, email, text.map { "\"\($0)\"" }, time, seconds.map { "\($0) s" }, start,
                  value.map { String(format: "%.0f%%", $0 * 100) }, on.map { $0 ? "on" : "off" }, key, destination,
                  app, goal] {
            if let v, !v.isEmpty { parts.append(v) }
        }
        return parts.joined(separator: " · ")
    }
}

/// What the planner made of a request: a short reply for the user, and the steps.
struct Plan: Codable {
    var reply: String?
    var steps: [PlanStep]
}

struct AlarmInfo: AlarmMetadata {}

enum DirectError: LocalizedError {
    case notAllowed(String)
    case missing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed(let what): return "No permission for \(what) (iPhone Settings → Mantiza)"
        case .missing(let what): return "Missing \(what)"
        case .failed(let what): return what
        }
    }
}

/// Things Mantiza does straight through iOS frameworks: no other app, no screen, no AI.
@MainActor
enum Direct {

    // MARK: Alarms and timers (AlarmKit, iOS 26+)

    private static func alarmsAllowed() async throws {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { _ = try await manager.requestAuthorization() }
        guard manager.authorizationState == .authorized else { throw DirectError.notAllowed("alarms") }
    }

    private static func attributes(_ label: String) -> AlarmAttributes<AlarmInfo> {
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(String.LocalizationValue(label)))
        return AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: AlarmInfo(), tintColor: .pink)
    }

    /// Alarm at a clock time, once or on some weekdays. Returns a description for the log.
    static func alarm(time: String, days: [String], label: String?) async throws -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            throw DirectError.missing("a time like 07:30")
        }
        try await alarmsAllowed()
        let weekdays = days.compactMap(weekday)
        let schedule = Alarm.Schedule.relative(.init(time: .init(hour: parts[0], minute: parts[1]),
                                                     repeats: weekdays.isEmpty ? .never : .weekly(weekdays)))
        let config = AlarmManager.AlarmConfiguration<AlarmInfo>.alarm(schedule: schedule,
                                                                     attributes: attributes(label ?? "Alarm"))
        _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: config)
        return String(format: "%02d:%02d", parts[0], parts[1]) + (weekdays.isEmpty ? "" : " on " + days.joined(separator: ", "))
    }

    /// A timer, as an alarm at "now + seconds" (Apple's countdown style needs a widget extension).
    static func timer(seconds: Int, label: String?) async throws -> String {
        guard seconds > 0 else { throw DirectError.missing("how long") }
        try await alarmsAllowed()
        let fire = Date().addingTimeInterval(TimeInterval(seconds))
        let config = AlarmManager.AlarmConfiguration<AlarmInfo>.alarm(schedule: .fixed(fire),
                                                                     attributes: attributes(label ?? "Timer"))
        _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: config)
        return "rings at " + fire.formatted(date: .omitted, time: .shortened)
    }

    private static func weekday(_ name: String) -> Locale.Weekday? {
        switch name.lowercased().prefix(3) {
        case "mon": return .monday
        case "tue": return .tuesday
        case "wed": return .wednesday
        case "thu": return .thursday
        case "fri": return .friday
        case "sat": return .saturday
        case "sun": return .sunday
        default: return nil
        }
    }

    // MARK: Calendar and reminders (EventKit)

    private static let store = EKEventStore()

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func event(title: String, start: String?, end: String?) async throws -> String {
        guard let from = parseDate(start) else { throw DirectError.missing("when the event starts") }
        guard try await store.requestWriteOnlyAccessToEvents() else { throw DirectError.notAllowed("the calendar") }
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = from
        e.endDate = parseDate(end) ?? from.addingTimeInterval(3600)
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
        return "\"\(title)\" on " + from.formatted(date: .abbreviated, time: .shortened)
    }

    static func reminder(title: String, due: String?) async throws -> String {
        guard try await store.requestFullAccessToReminders() else { throw DirectError.notAllowed("reminders") }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.defaultCalendarForNewReminders()
        if let d = parseDate(due) {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            r.addAlarm(EKAlarm(absoluteDate: d))
        }
        try store.save(r, commit: true)
        return "\"\(title)\"" + (parseDate(due).map { " at " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
    }

    // MARK: Screen and flashlight

    /// Exact brightness; stays until the phone locks, even after Mantiza closes (Apple docs).
    static func brightness(_ value: Double) {
        UIScreen.main.brightness = CGFloat(min(max(value, 0), 1))
    }

    /// Flashlight straight through the camera torch. Returns whether iOS says it is now as asked.
    static func flashlight(_ on: Bool) async -> Bool {
        guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch,
              camera.isTorchModeSupported(on ? .on : .off) else { return false }
        do {
            try camera.lockForConfiguration()
            camera.torchMode = on ? .on : .off
            camera.unlockForConfiguration()
        } catch { return false }
        try? await Task.sleep(for: .milliseconds(400))
        return camera.isTorchActive == on
    }

    // MARK: Contacts

    struct Person {
        var id: String = ""  // the contact's identifier ("" for a number typed by the user)
        let name: String
        let phone: String?   // international digits, e.g. 919812345678
        let email: String?
    }

    private static let contactKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                                      CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]

    private static func contactsAllowed(_ store: CNContactStore) async -> Bool {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status == .limited
    }

    private static func person(_ c: CNContact, fallbackName: String) -> Person {
        let mobile = c.phoneNumbers.first { [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone].contains($0.label ?? "") }
            ?? c.phoneNumbers.first
        let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return Person(id: c.identifier, name: full.isEmpty ? fallbackName : full,
                      phone: mobile.map { international($0.value.stringValue) },
                      email: c.emailAddresses.first.map { String($0.value) })
    }

    /// Everyone in Contacts whose name matches what the user said, and whether the match is clear:
    /// one person only, a full name typed exactly, or the person the user picked last time for
    /// this name. When it isn't clear, Mantiza asks "Which Azad?" and remembers the answer.
    static func lookUp(_ name: String) async -> (people: [Person], clear: Person?) {
        let store = CNContactStore()
        guard await contactsAllowed(store) else { return ([], nil) }
        let found = ((try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name),
                                                 keysToFetch: contactKeys)) ?? []).map { person($0, fallbackName: name) }
        let reachable = found.filter { $0.phone != nil || $0.email != nil }
        let people = reachable.isEmpty ? found : reachable
        if people.count == 1 { return (people, people[0]) }
        let said = name.lowercased().trimmingCharacters(in: .whitespaces)
        let exact = people.filter { $0.name.lowercased() == said }
        if exact.count == 1 { return (people, exact[0]) }
        if let id = UserDefaults.standard.string(forKey: aliasKey(name)), let picked = people.first(where: { $0.id == id }) {
            return (people, picked)
        }
        return (people, nil)
    }

    /// Remembers which contact the user means by a name ("Azad" → Azad Jagtap).
    static func remember(_ person: Person, for name: String) {
        UserDefaults.standard.set(person.id, forKey: aliasKey(name))
    }

    private static func aliasKey(_ name: String) -> String {
        "contact.alias." + name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// "+91 98123 45678", "098123 45678" or "98123 45678" → "919812345678" (country from the phone's region).
    static func international(_ raw: String) -> String {
        let plus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        var digits = raw.filter(\.isNumber)
        if plus { return digits }
        if digits.hasPrefix("00") { return String(digits.dropFirst(2)) }
        let code = callingCodes[Locale.current.region?.identifier ?? ""] ?? ""
        if digits.hasPrefix("0") { digits.removeFirst() }
        if !code.isEmpty, digits.count <= 10 { return code + digits }
        return digits
    }

    private static let callingCodes = ["IN": "91", "US": "1", "CA": "1", "GB": "44", "AE": "971", "AU": "61",
                                       "DE": "49", "FR": "33", "SG": "65", "SA": "966", "NP": "977", "BD": "880",
                                       "PK": "92", "LK": "94", "JP": "81", "CN": "86", "IT": "39", "ES": "34"]

    // MARK: Links

    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func whatsAppURL(phone: String, text: String?) -> URL? {
        URL(string: "https://wa.me/\(phone)" + (text.map { "?text=" + encode($0) } ?? ""))
    }

    static func smsURL(phone: String, text: String?) -> URL? {
        URL(string: "sms:+\(phone)" + (text.map { "&body=" + encode($0) } ?? ""))
    }

    static func callURL(phone: String) -> URL? { URL(string: "tel:+\(phone)") }

    static func mailURL(to: String, subject: String?, body: String?) -> URL? {
        var q: [String] = []
        if let subject { q.append("subject=" + encode(subject)) }
        if let body { q.append("body=" + encode(body)) }
        return URL(string: "mailto:\(to)" + (q.isEmpty ? "" : "?" + q.joined(separator: "&")))
    }

    static func directionsURL(to place: String, mode: String?, google: Bool) -> URL? {
        let m = (mode ?? "driving").lowercased()
        if google {
            let gm = m == "cycling" ? "bicycling" : m
            return URL(string: "comgooglemaps://?daddr=\(encode(place))&directionsmode=\(gm)")
        }
        // Unified Maps URLs, iOS 18.4+ (Apple docs)
        return URL(string: "https://maps.apple.com/directions?destination=\(encode(place))&mode=\(m)")
    }

    /// Opens a link in its app. Works only while Mantiza is on screen.
    static func open(_ url: URL, appOnly: Bool = false) async -> Bool {
        await UIApplication.shared.open(url, options: appOnly ? [.universalLinksOnly: true] : [:])
    }
}
