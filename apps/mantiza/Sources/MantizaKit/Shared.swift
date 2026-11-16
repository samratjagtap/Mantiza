import Foundation

/// What the app and the widget share (App Group storage): recent tasks for one-tap buttons, and
/// the last task's result.
public enum Shared {
    public static let group = "group.com.samratjagtap.Mantiza"
    static var store: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    public struct LastTask: Codable, Sendable {
        public let prompt: String
        public let ok: Bool
        public let result: String
        public let when: Date
    }

    /// Shown in the widget before Mantiza has done anything.
    public static let starters = ["Turn on the flashlight", "Timer for 10 minutes", "Volume up",
                                  "Remind me to drink water in 1 hour", "Brightness to 40%", "Turn on Do Not Disturb"]

    /// Recent tasks that worked, newest first, without repeats.
    public static var recents: [String] {
        store.stringArray(forKey: "recents") ?? []
    }

    public static var last: LastTask? {
        guard let data = store.data(forKey: "last") else { return nil }
        return try? JSONDecoder().decode(LastTask.self, from: data)
    }

    /// Called by the app when a task ends.
    public static func record(prompt: String, ok: Bool, result: String) {
        let task = LastTask(prompt: prompt, ok: ok, result: result, when: Date())
        if let data = try? JSONEncoder().encode(task) { store.set(data, forKey: "last") }
        guard ok else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(prompt) != .orderedSame }
        list.insert(prompt, at: 0)
        store.set(Array(list.prefix(8)), forKey: "recents")
        var runs = history
        runs.append(Run(prompt: prompt, when: task.when))
        if let data = try? JSONEncoder().encode(Array(runs.suffix(400))) { store.set(data, forKey: "history") }
    }

    // MARK: - Habits: what you usually ask around this time

    /// One task that worked, and when.
    public struct Run: Codable, Sendable {
        public let prompt: String
        public let when: Date
    }

    /// A task the widget or the app offers. `habit`: you usually ask it around this time.
    public struct Suggestion: Hashable, Sendable {
        public let prompt: String
        public let habit: Bool
        public init(prompt: String, habit: Bool) {
            self.prompt = prompt
            self.habit = habit
        }
    }

    /// Every task that worked (the last 400), oldest first. Stays on the phone.
    public static var history: [Run] {
        guard let data = store.data(forKey: "history") else { return [] }
        return (try? JSONDecoder().decode([Run].self, from: data)) ?? []
    }

    public static func forgetHabits() {
        store.removeObject(forKey: "history")
    }

    /// Tasks for a moment in time: first the ones you usually ask around then, then recent ones,
    /// then starters.
    ///
    /// A task counts as a habit when it worked on at least 2 different days within 90 minutes of
    /// this time of day. Each past run adds to its score: more when it is closer in time of day,
    /// on the same weekday (or the same kind of day, weekday or weekend), and more recent (a run
    /// from 3 weeks ago counts half).
    public static func suggestions(at date: Date = Date(), count: Int, from runs: [Run]? = nil) -> [Suggestion] {
        let runs = runs ?? history
        let cal = Calendar.current
        func minutes(_ d: Date) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let nowMinutes = minutes(date)
        let weekday = cal.component(.weekday, from: date)
        let weekend = cal.isDateInWeekend(date)

        var score: [String: Double] = [:], days: [String: Set<Date>] = [:], shown: [String: String] = [:]
        for run in runs where run.when <= date {
            let key = run.prompt.trimmingCharacters(in: .whitespaces).lowercased()
            shown[key] = run.prompt
            var gap = abs(minutes(run.when) - nowMinutes)
            gap = min(gap, 1440 - gap)  // 23:50 and 00:10 are 20 minutes apart
            guard gap <= 90 else { continue }
            let age = date.timeIntervalSince(run.when) / 86400
            let fresh = pow(0.5, age / 21)
            let near = exp(-pow(gap / 60, 2))
            let sameDay = cal.component(.weekday, from: run.when) == weekday ? 1.0
                : (cal.isDateInWeekend(run.when) == weekend ? 0.7 : 0.4)
            score[key, default: 0] += fresh * near * sameDay
            days[key, default: []].insert(cal.startOfDay(for: run.when))
        }
        var out: [Suggestion] = []
        var used = Set<String>()
        let habits = score.filter { (days[$0.key]?.count ?? 0) >= 2 && $0.value >= 0.6 }.sorted { $0.value > $1.value }
        for (key, _) in habits where out.count < count {
            out.append(Suggestion(prompt: shown[key] ?? key, habit: true))
            used.insert(key)
        }
        for p in recents + starters where out.count < count {
            let key = p.trimmingCharacters(in: .whitespaces).lowercased()
            if used.insert(key).inserted { out.append(Suggestion(prompt: p, habit: false)) }
        }
        return out
    }

    /// The tasks the widget offers: recent ones first, then starters.
    public static func quickTasks(_ count: Int) -> [String] {
        var out = recents
        for s in starters where out.count < count && !out.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
            out.append(s)
        }
        return Array(out.prefix(count))
    }

    /// mantiza://run?q=... runs a task; mantiza://new opens the app ready for a new one.
    public static func runURL(_ prompt: String) -> URL {
        var c = URLComponents()
        c.scheme = "mantiza"
        c.host = "run"
        c.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return c.url ?? newURL
    }

    public static let newURL = URL(string: "mantiza://new")!
    /// Opens Mantiza already listening (voice).
    public static let listenURL = URL(string: "mantiza://listen")!
    /// Stops the running task.
    public static let stopURL = URL(string: "mantiza://stop")!

    /// Whether iOS can run Mantiza's actions (Siri, buttons that work without opening the app):
    /// only when the build packed the App Intents index (scripts/make_intents.py). Without it, a
    /// button that runs an action does nothing, so buttons fall back to links that open the app.
    public static let actionsIndexed: Bool = {
        guard let url = Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = json["actions"] as? [String: Any] else { return false }
        return actions["StopTaskIntent"] != nil
    }()

    public static func prompt(from url: URL) -> String? {
        guard url.scheme == "mantiza", url.host == "run" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    }
}
