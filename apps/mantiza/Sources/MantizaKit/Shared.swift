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

    public static func prompt(from url: URL) -> String? {
        guard url.scheme == "mantiza", url.host == "run" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    }
}
