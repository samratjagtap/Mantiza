import Foundation

/// One finished run, saved as JSON in Documents/runs (timings feed the speed comparisons, PRD T11/T12).
struct RunRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var request: String
    var plan: Subtask?
    var steps: [AgentRunner.Step]
    var outcome: String
    var success: Bool
    var bigBrain: String
    /// Set when this run replayed a saved workflow.
    var workflowID: UUID?

    var totalMs: Int { steps.reduce(0) { $0 + $1.ms + $1.captureMs + $1.ocrMs + $1.actMs } }
    /// Steps decided by the big brain (plus planning and the final check), and by Jev.
    var bigCalls: Int { steps.filter { $0.source == "claude" || $0.source == "gemini" }.count + (plan == nil ? 0 : 1) }
    var fastCalls: Int { steps.filter { $0.source == "jev" }.count }
}

/// Run history on disk. Each run is its own file, so a crash never loses the others.
@MainActor final class RunStore {
    let folder: URL
    private(set) var runs: [RunRecord] = []

    init(folder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("runs")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func url(_ r: RunRecord) -> URL { folder.appendingPathComponent("\(r.id.uuidString).json") }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        runs = files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(RunRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func save(_ r: RunRecord) {
        if let data = try? Self.encoder.encode(r) { try? data.write(to: url(r), options: .atomic) }
        runs.removeAll { $0.id == r.id }
        runs.insert(r, at: 0)
    }

    func delete(_ r: RunRecord) {
        try? FileManager.default.removeItem(at: url(r))
        runs.removeAll { $0.id == r.id }
    }

    func deleteAll() {
        runs.forEach { try? FileManager.default.removeItem(at: url($0)) }
        runs = []
    }
}
