import Foundation

/// Training rows for Laya: the quick picker's questions about one screen, answered with what the big brain
/// decided there. Rows from successful runs are the labels `tools/laya/train.sh` fine-tunes on; rows from
/// failed runs are kept apart for analysis. Format: Laya's `{state, questions, expected}` JSONL.
enum TrainingLog {
    /// Laya's server takes at most 100 options per choice; train on the same elements it will be shown.
    static let elements = 60

    /// One row, or nil when the decision has nothing the quick picker could have answered.
    static func row(_ c: DecisionContext, decision: AgentAction, verified: Bool? = nil, step: Int) -> [String: Any]? {
        let elements = Array(c.reading.elements.prefix(Self.elements))
        let expected = Self.expected(decision, elements: elements, inputs: c.subtask.inputs, checks: c.subtask.verification.count,
                                     verified: verified)
        guard !expected.isEmpty else { return nil }
        var body = SystemOnePicker.body(c, elements: elements)
        body["model"] = nil
        body["expected"] = expected
        body["step"] = step
        return body
    }

    /// The quick picker's answers that match the big brain's decision. Questions left out are not trained.
    static func expected(_ action: AgentAction, elements: [ScreenElement], inputs: [String], checks: Int,
                         verified: Bool?) -> [String: Any] {
        switch action {
        case let .tap(element, _):
            // A tap on something not in the list (an icon, a coordinate) is what NEEDS_AGENT means.
            guard let id = element, elements.contains(where: { $0.id == id }) else { return ["operation": "NEEDS_AGENT"] }
            return ["operation": "TAP", "tap_target": "e\(id)"]
        case let .type(text):
            guard let i = inputs.firstIndex(of: text) else { return [:] }
            return ["operation": "TYPE_TEXT", "text_input": "t\(i)"]
        case let .scroll(down): return ["operation": down ? "SCROLL_DOWN" : "SCROLL_UP"]
        case .back: return ["operation": "BACK"]
        case .home: return ["operation": "HOME"]
        case .wait: return ["operation": "WAIT"]
        case .openApp: return ["operation": "NEEDS_AGENT"]
        case .blocked: return ["operation": "BLOCKED"]
        case .done:
            // Only a done the independent check confirmed says what the screen shows.
            guard verified == true else { return [:] }
            var e: [String: Any] = ["operation": "DONE"]
            for i in 0..<checks { e["verify_\(i)"] = true }
            return e
        }
    }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "training")
    }

    /// Save a run's rows: `training/gold/<run>.jsonl` when it succeeded, else `training/failed/`.
    static func save(_ rows: [[String: Any]], run: UUID, success: Bool) {
        guard !rows.isEmpty else { return }
        let dir = folder.appending(path: success ? "gold" : "failed")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = rows.compactMap { row -> String? in
            var row = row
            row["run"] = run.uuidString
            guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: dir.appending(path: "\(run.uuidString).jsonl"),
                                                         atomically: true, encoding: .utf8)
        Log.event("training.saved", ["rows": lines.count, "gold": success])
    }

    static func deleteAll() { try? FileManager.default.removeItem(at: folder) }
}
