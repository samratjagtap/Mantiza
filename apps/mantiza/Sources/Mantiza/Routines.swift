import CoreGraphics
import Foundation

// Record once, replay without AI (idea from mozarkai/optics-framework, Apache 2.0; see
// Docs/Mantiza Roadmap/optics-framework-research.md). A screen task the AI finished is saved as
// steps; each step remembers the words on screen before it, what it tapped (by its words, or by a
// nearby word for icons and switches), and the words that appeared or went away after it.
// A replay checks all three with on-phone text reading only; when a check fails, the AI takes over
// from there and the routine is updated.

/// A screen task learned from one successful AI run.
struct Routine: Codable, Identifiable {
    var name: String          // the kind of task, e.g. "settings: turn off wi-fi"
    var app: String?
    var steps: [RoutineStep]
    var replays: Int = 0      // successful replays without AI
    var learned: Date = Date()
    var id: String { name }
}

struct RoutineStep: Codable {
    enum Kind: String, Codable { case tap, type, scroll }
    var kind: Kind
    var before: [String]      // words on screen before the step
    var label: String         // words of what is tapped ("" for icons and switches); may be "{person}"
    var anchor: String        // nearby words, to find a target that has none
    var dx: Double            // target minus anchor centre, as a fraction of the screen
    var dy: Double
    var x: Double             // where the target was, as a fraction of the screen
    var y: Double
    var text: String?         // typed text, usually "{text}"
    var appear: [String]      // words that appeared after the step
    var vanish: [String]      // words that went away after the step
    var what: String          // for the log
}

/// Learned routines, kept in a file on the phone.
@MainActor
final class RoutineStore: ObservableObject {
    @Published private(set) var all: [Routine] = []

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("routines.json")
    }

    init() {
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([Routine].self, from: data) {
            all = list.filter { r in !(Self.retired[r.name].map { r.learned < $0 } ?? false) }
            if all.count != list.count { write() }
        }
    }

    /// Routines learned wrongly by older builds: dropped on start if learned before the date.
    /// - WhatsApp send routine had learned "Open in WhatsApp Business" (debug run 2026-11-10_111607).
    /// - "clock: check alarms" had learned to flip an alarm's switch (debug run 2026-11-13_135928).
    /// - Instagram routines learned while Instagram hadn't opened (debug runs 2026-11-10_112947, _113142).
    private static let retired: [String: Date] = [
        "whatsapp: tap send after the link opened the chat": .distantFuture,
        "instagram: open dms": cutoff,
        "instagram: open the profile of {person}": cutoff,
        // Learned tapping the 10:22 AM alarm's switch while only checking alarms (2026-11-13_135928).
        "clock: check alarms": ISO8601DateFormatter().date(from: "2026-11-13T20:30:00+05:30")!,
    ]
    private static let cutoff = ISO8601DateFormatter().date(from: "2026-11-10T12:30:00+05:30")!

    var names: [String] { all.map(\.name) }

    /// The words of an app's start screen: what the first step of its routines expects to see
    /// (words found on at least half of them). Nil until a routine for the app was learned.
    func startWords(app: String) -> [String]? {
        let firsts = all.filter { ($0.app ?? "").lowercased() == app.lowercased() }.compactMap { $0.steps.first?.before }
        guard !firsts.isEmpty else { return nil }
        if firsts.count == 1 { return firsts[0] }
        var counts: [String: Int] = [:]
        for words in firsts { for w in Set(words) { counts[w, default: 0] += 1 } }
        let common = counts.filter { $0.value * 2 >= firsts.count }.map(\.key)
        return common.isEmpty ? nil : common
    }

    func find(_ name: String?) -> Routine? {
        guard let name else { return nil }
        let key = Words.norm(name)
        return all.first { Words.norm($0.name) == key }
    }

    func save(_ routine: Routine) {
        all.removeAll { Words.norm($0.name) == Words.norm(routine.name) }
        all.append(routine)
        write()
    }

    func delete(_ name: String) {
        all.removeAll { $0.name == name }
        write()
    }

    func deleteAll() {
        all = []
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: file, options: .atomic) }
    }
}

/// Word handling for routines: everything compares normalised text.
enum Words {
    /// Lowercase, no accents, letters/digits/spaces only ("Wi‑Fi" → "wi fi").
    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Words worth remembering: not times, counts, or tiny fragments that change from run to run.
    static func stable(_ s: String) -> Bool {
        let letters = s.filter(\.isLetter).count
        let digits = s.filter(\.isNumber).count
        return letters >= 3 && digits * 2 <= letters && s.count <= 40
    }

    /// The screen's stable words, without the task's own values (a name or message changes each time).
    static func screenWords(_ items: [ScreenItem], excluding values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let w = norm(item.text)
            guard stable(w), !seen.contains(w), !values.contains(where: { !$0.isEmpty && w.contains($0) }) else { continue }
            seen.insert(w)
            out.append(w)
        }
        return out
    }

    static func present(_ word: String, in screen: [String]) -> Bool {
        screen.contains { $0 == word || (word.count >= 4 && ($0.contains(word) || word.contains($0) && $0.count >= 4)) }
    }

    /// Share of the remembered words that are on screen now (1 = all of them).
    static func match(_ remembered: [String], _ screen: [String]) -> Double {
        guard !remembered.isEmpty else { return 1 }
        return Double(remembered.filter { present($0, in: screen) }.count) / Double(remembered.count)
    }

    /// 0…1 similarity of two short strings (edit distance).
    static func similar(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return x.isEmpty && y.isEmpty ? 1 : 0 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Fills "{person}"-style blanks from the task's values.
    static func fill(_ s: String, _ values: [String: String]) -> String? {
        var out = s
        for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out.contains("{") && out.contains("}") ? nil : out
    }

    /// Turns a tapped label or typed text back into a blank if it is one of the task's values.
    static func blank(_ s: String, _ values: [String: String]) -> String {
        let n = norm(s)
        for (k, v) in values.sorted(by: { $0.value.count > $1.value.count }) {
            let nv = norm(v)
            if nv.count >= 2, n == nv || (nv.count >= 3 && n.contains(nv)) { return "{\(k)}" }
        }
        return s
    }

    /// Words that appeared and went away between two screens (at most 4 each, longest first).
    static func changes(from before: [String], to after: [String]) -> (appear: [String], vanish: [String]) {
        let appear = after.filter { !present($0, in: before) }.sorted { $0.count > $1.count }.prefix(4)
        let vanish = before.filter { !present($0, in: after) }.sorted { $0.count > $1.count }.prefix(4)
        return (Array(appear), Array(vanish))
    }
}

/// Finding things on a frame by their words.
enum Finder {
    /// The item whose words best match `label`, closest to where it was last time.
    static func item(_ label: String, in items: [ScreenItem], near: CGPoint?, size: CGSize) -> ScreenItem? {
        let want = Words.norm(label)
        guard !want.isEmpty else { return nil }
        func distance(_ i: ScreenItem) -> CGFloat {
            guard let near else { return 0 }
            return hypot(i.center.x / size.width - near.x, i.center.y / size.height - near.y)
        }
        let exact = items.filter { Words.norm($0.text) == want }
        if let best = exact.min(by: { distance($0) < distance($1) }) { return best }
        let close = items.filter {
            let t = Words.norm($0.text)
            return (want.count >= 3 && t.contains(want)) || Words.similar(t, want) >= 0.8
        }
        return close.min(by: { distance($0) < distance($1) })
    }

    /// The text item a point falls on, if any.
    static func item(at p: CGPoint, in items: [ScreenItem]) -> ScreenItem? {
        items.first { $0.box.insetBy(dx: -6, dy: -6).contains(p) }
    }

    /// A stable text item near a point, preferring the same row (for switches next to their label).
    static func anchor(for p: CGPoint, in items: [ScreenItem], size: CGSize) -> ScreenItem? {
        items.filter { Words.stable(Words.norm($0.text)) }.min { a, b in
            func cost(_ i: ScreenItem) -> CGFloat {
                let dy = abs(i.center.y - p.y) / size.height
                let dx = abs(i.center.x - p.x) / size.width
                return dy * 3 + dx + (dy < 0.025 ? 0 : 0.5)
            }
            return cost(a) < cost(b)
        }
    }
}
