import CoreGraphics
import Foundation

/// The phone's screens and the taps between them, learned from runs: each screen is known by its stable labels
/// (titles, rows, tabs; not times, counts or list contents), each edge by the tap that led from one screen to
/// another. A known screen is then reached by walking the cheapest path, with no AI, checking every landing.
struct PhoneMap: Codable, Equatable {
    struct Screen: Codable, Equatable, Identifiable {
        var id: String  // "s12": short, so the planner can name it
        var app: String
        var title: String
        /// Label -> on how many visits it was on screen.
        var counts: [String: Int]
        var visits: Int
        var lastSeen: Date

        /// Labels seen on at least half the visits: list contents come and go, titles and rows stay.
        var anchors: Set<String> { Set(counts.filter { $0.value * 2 >= visits }.keys) }
    }

    struct Edge: Codable, Equatable {
        var from: String
        var to: String
        var action: RecordedAction  // a labelled tap or back
        var ok = 1
        /// Misses in a row (landed elsewhere, or the label was gone); 3 drops the edge.
        var failed = 0
        var lastOK: Date
    }

    private(set) var screens: [Screen] = []
    private(set) var edges: [Edge] = []
    private var nextID = 1

    /// At least this score is the same screen; from `similar` up, it is when the title is still on screen
    /// (an app redesign that kept the page's name).
    static let same = 0.6
    static let similar = 0.35
    static let maxLabels = 40
    static let maxFailures = 3
    /// Screens not seen for this long are forgotten (the app may be gone or redesigned).
    static let forgetAfter: TimeInterval = 90 * 86_400

    func screen(_ id: String) -> Screen? { screens.first { $0.id == id } }

    // MARK: Recognising screens

    /// The labels that can identify a screen: short text without digits (no times, prices, counts or codes).
    static func labels(_ r: ScreenReading) -> [String] {
        var seen = Set<String>()
        return r.elements.compactMap { e -> String? in
            let t = normalize(e.text)
            guard t.count <= 32, t.filter(\.isLetter).count >= 2, !t.contains(where: \.isNumber),
                  t.split(separator: " ").count <= 4, seen.insert(t).inserted else { return nil }
            return t
        }.prefix(maxLabels).map { $0 }
    }

    /// The page title: the first label in the top quarter of the screen, else the first label.
    static func title(_ r: ScreenReading) -> String {
        let top = r.elements.filter { $0.box.minY < 0.25 }.map { normalize($0.text) }
        let all = labels(r)
        return top.first(where: all.contains) ?? all.first ?? ""
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// How well a reading's labels fit a screen: shared anchors, with extra labels (list contents) counting little.
    static func score(_ s: Screen, _ labels: Set<String>) -> Double {
        let anchors = s.anchors
        guard !anchors.isEmpty else { return 0 }
        let shared = anchors.intersection(labels).count
        return Double(shared) / (Double(anchors.count) + 0.3 * Double(labels.subtracting(anchors).count))
    }

    /// The known screen of this app the reading shows, or nil.
    func match(_ r: ScreenReading, app: String) -> Screen? {
        let labels = Set(Self.labels(r))
        let best = screens.filter { $0.app == app }.map { ($0, Self.score($0, labels)) }.max { $0.1 < $1.1 }
        guard let (s, score) = best else { return nil }
        if score >= Self.same || (score >= Self.similar && !s.title.isEmpty && labels.contains(s.title)) { return s }
        return nil
    }

    /// Note a look at the screen: the matching screen learns its labels again, or a new screen is added.
    mutating func observe(_ r: ScreenReading, app: String, at now: Date = Date()) -> String? {
        let labels = Self.labels(r)
        guard labels.count >= 2 else { return nil }  // a blank or loading screen identifies nothing
        if let known = match(r, app: app), let i = screens.firstIndex(where: { $0.id == known.id }) {
            screens[i].visits += 1
            screens[i].lastSeen = now
            for l in labels { screens[i].counts[l, default: 0] += 1 }
            if screens[i].visits >= 4 {  // drop what was there only once in a while
                let v = screens[i].visits
                screens[i].counts = screens[i].counts.filter { $0.value * 4 >= v }
            }
            return known.id
        }
        let id = "s\(nextID)"
        nextID += 1
        screens.append(Screen(id: id, app: app, title: Self.title(r), counts: Dictionary(uniqueKeysWithValues: labels.map { ($0, 1) }),
                              visits: 1, lastSeen: now))
        return id
    }

    // MARK: Edges

    /// Only labelled taps and back are walked: an icon tap has no text to find again, and risky taps never go
    /// on the map.
    static func walkable(_ a: RecordedAction) -> Bool {
        a.kind == "back" || (a.kind == "tap" && !(a.target ?? "").isEmpty)
    }

    static func key(_ a: RecordedAction) -> String { a.kind + ":" + normalize(a.target ?? "") }

    /// The action led from one screen to another.
    mutating func record(from: String, _ action: RecordedAction, to: String, at now: Date = Date()) {
        guard from != to, Self.walkable(action) else { return }
        if let i = edges.firstIndex(where: { $0.from == from && $0.to == to && Self.key($0.action) == Self.key(action) }) {
            edges[i].ok += 1
            edges[i].failed = 0
            edges[i].lastOK = now
            edges[i].action.point = action.point ?? edges[i].action.point
        } else {
            edges.append(Edge(from: from, to: to, action: action, lastOK: now))
        }
    }

    /// The edge did not take the agent where it used to; after `maxFailures` in a row it is dropped.
    mutating func failed(_ edge: Edge) {
        guard let i = edges.firstIndex(where: { $0.from == edge.from && $0.to == edge.to && Self.key($0.action) == Self.key(edge.action) })
        else { return }
        edges[i].failed += 1
        if edges[i].failed >= Self.maxFailures { edges.remove(at: i) }
    }

    /// Cost of walking an edge: one step, more for recent misses and for paths not used in a long time.
    static func cost(_ e: Edge, now: Date) -> Double {
        1 + 2 * Double(e.failed) + max(0, now.timeIntervalSince(e.lastOK)) / (60 * 86_400)
    }

    /// The cheapest path between two screens ([] when already there), or nil when there is none.
    func route(from: String, to: String, now: Date = Date()) -> [Edge]? {
        if from == to { return [] }
        var best: [String: Double] = [from: 0]
        var via: [String: Edge] = [:]
        var open: Set<String> = [from]
        var done = Set<String>()
        while let here = open.min(by: { best[$0]! < best[$1]! }) {
            open.remove(here)
            if here == to { break }
            done.insert(here)
            for e in edges where e.from == here && !done.contains(e.to) {
                let c = best[here]! + Self.cost(e, now: now)
                if c < best[e.to] ?? .infinity {
                    best[e.to] = c
                    via[e.to] = e
                    open.insert(e.to)
                }
            }
        }
        guard via[to] != nil else { return nil }
        var path: [Edge] = []
        var at = to
        while at != from, let e = via[at] { path.insert(e, at: 0); at = e.from }
        return path
    }

    // MARK: Upkeep

    /// Forget screens not seen for `forgetAfter`, and their edges.
    mutating func prune(now: Date = Date()) {
        screens.removeAll { now.timeIntervalSince($0.lastSeen) > Self.forgetAfter }
        let ids = Set(screens.map(\.id))
        edges.removeAll { !ids.contains($0.from) || !ids.contains($0.to) }
    }

    /// Known screens for the planner, most recently seen first: "s3 | settings | general | about, storage, …".
    func index(limit: Int = 120) -> String {
        screens.sorted { $0.lastSeen > $1.lastSeen }.prefix(limit).map { s in
            let others = s.anchors.subtracting([s.title]).sorted().prefix(8)
            return "\(s.id) | \(s.app) | \(s.title) | \(others.joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}

/// The phone map on disk (Documents/phonemap.json).
@MainActor final class MapStore {
    let file: URL
    private(set) var map = PhoneMap()

    init(file: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("phonemap.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? RunStore.decoder.decode(PhoneMap.self, from: data) {
            map = saved
            map.prune()
        }
    }

    private func persist() {
        if let data = try? RunStore.encoder.encode(map) { try? data.write(to: file, options: .atomic) }
    }

    func observe(_ r: ScreenReading, app: String) -> String? {
        let id = map.observe(r, app: app)
        persist()
        return id
    }

    func record(from: String, _ action: RecordedAction, to: String) {
        map.record(from: from, action, to: to)
        persist()
    }

    func failed(_ edge: PhoneMap.Edge) {
        map.failed(edge)
        persist()
    }

    func deleteAll() {
        map = PhoneMap()
        persist()
    }

    /// Apps are matched by name, case and spacing aside.
    nonisolated static func app(_ name: String?) -> String? {
        guard let n = name.map(PhoneMap.normalize), !n.isEmpty else { return nil }
        return n
    }
}
