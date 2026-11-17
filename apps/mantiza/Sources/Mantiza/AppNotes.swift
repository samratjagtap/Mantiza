import Foundation

/// Short lessons about each app that Mantiza learns as it works ("Stories are the circles at the
/// top of the Home feed"). After a screen task that worked but had trouble on the way, the big brain
/// writes one lesson; the next task in that app gives the brains its notes, so they don't start from
/// zero. Kept on the phone; Device tab → App notes shows and forgets them.
@MainActor
final class AppNotes: ObservableObject {
    static let shared = AppNotes()

    struct Note: Codable, Hashable {
        var text: String
        var saved: Date
    }

    /// App name as shown to the user → its notes, newest first.
    @Published private(set) var all: [String: [Note]] = [:]

    private let perApp = 6

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-notes.json")
    }

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: [Note]].self, from: data) {
            all = saved
        }
    }

    /// The notes for an app, newest first ([] for none).
    func notes(for app: String?) -> [String] {
        guard let key = key(app) else { return [] }
        return all[key]?.map(\.text) ?? []
    }

    /// Adds a lesson. A lesson much like one already kept replaces it (newer wording wins).
    func add(_ text: String, app: String) {
        let lesson = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = key(app), lesson.count >= 8, lesson.count <= 200 else { return }
        var list = all[key] ?? []
        let new = Words.norm(lesson)
        list.removeAll { Words.similar(Words.norm($0.text), new) >= 0.7 }
        list.insert(Note(text: lesson, saved: Date()), at: 0)
        all[key] = Array(list.prefix(perApp))
        write()
    }

    func forget(app: String) {
        all[app] = nil
        write()
    }

    func forgetAll() {
        all = [:]
        write()
    }

    /// The stored name for an app: an existing entry with the same normalised name, else the name.
    private func key(_ app: String?) -> String? {
        guard let app, !Words.norm(app).isEmpty else { return nil }
        return all.keys.first { Words.norm($0) == Words.norm(app) } ?? app
    }

    private func write() {
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: file, options: .atomic) }
    }
}
