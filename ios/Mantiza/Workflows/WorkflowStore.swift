import Foundation

/// A task that worked once, saved so it can run again quickly: its plan and the steps that were taken.
struct Workflow: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var request: String
    var subtask: Subtask
    var steps: [RecordedAction]
    var created = Date()
    /// When it ran (successfully), for suggestions.
    var uses: [Date] = []
    var pinned = false

    init(id: UUID = UUID(), name: String, request: String, subtask: Subtask, steps: [RecordedAction]) {
        self.id = id
        self.name = name
        self.request = request
        self.subtask = subtask
        self.steps = steps
    }

    init?(from run: RunRecord) {
        guard run.success, let plan = run.plan else { return nil }
        let actions = run.steps.compactMap(\.recorded)
        guard !actions.isEmpty || plan.app != nil else { return nil }
        name = String(run.request.prefix(40))
        request = run.request
        subtask = plan
        steps = actions
        uses = [run.date]
    }
}

/// Saved workflows (Documents/workflows.json) and the time-of-day suggestion for the stick and the widget.
@MainActor final class WorkflowStore {
    let file: URL
    private(set) var workflows: [Workflow] = []

    init(file: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("workflows.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let list = try? RunStore.decoder.decode([Workflow].self, from: data) {
            workflows = list
        }
    }

    private func persist() {
        if let data = try? RunStore.encoder.encode(workflows) { try? data.write(to: file, options: .atomic) }
    }

    func add(_ w: Workflow) {
        workflows.removeAll { $0.request.lowercased() == w.request.lowercased() }
        workflows.insert(w, at: 0)
        persist()
    }

    func update(_ w: Workflow) {
        guard let i = workflows.firstIndex(where: { $0.id == w.id }) else { return }
        workflows[i] = w
        persist()
    }

    func delete(_ w: Workflow) {
        workflows.removeAll { $0.id == w.id }
        persist()
    }

    func deleteAll() {
        workflows = []
        persist()
    }

    func used(_ id: UUID, at date: Date = Date()) {
        guard let i = workflows.firstIndex(where: { $0.id == id }) else { return }
        workflows[i].uses = Array((workflows[i].uses + [date]).suffix(50))
        persist()
    }

    func workflow(_ id: UUID) -> Workflow? { workflows.first { $0.id == id } }

    enum Bucket: String, CaseIterable { case morning, afternoon, evening, night }

    nonisolated static func bucket(_ d: Date, calendar: Calendar = .current) -> Bucket {
        switch calendar.component(.hour, from: d) {
        case 5..<11: return .morning
        case 11..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }

    /// How likely the workflow is wanted now: past uses in the same part of the day, recent ones counting more
    /// (two-week half-life), plus a little for pinned ones.
    nonisolated static func score(_ w: Workflow, now: Date = Date()) -> Double {
        let bucket = Self.bucket(now)
        let uses = w.uses.filter { Self.bucket($0) == bucket }
            .map { exp(-now.timeIntervalSince($0) / 86_400 / 14 * log(2)) }.reduce(0, +)
        return uses + (w.pinned ? 0.5 : 0)
    }

    /// Best workflows for now, best first; only those with some reason to show.
    func suggestions(now: Date = Date(), limit: Int = 4) -> [Workflow] {
        workflows.map { ($0, Self.score($0, now: now)) }.filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
