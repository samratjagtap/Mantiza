import Foundation

/// Gemini through the Generative Language REST API, as the alternative big brain. Answers are requested as
/// JSON and checked by the same parser as Claude's.
struct GeminiBrain: BigBrain {
    /// From the PRD (Google lists it for computer use); editable in Settings in case the id changes.
    static let defaultModel = "gemini-3.8-flash"

    let key: String
    var model = GeminiBrain.defaultModel
    var name: String { "Gemini (\(model))" }

    func plan(_ request: String) async throws -> Subtask {
        let fields = "Fields: goal (string), app (string or null), inputs (array of strings), verification (array of strings), allowed_risks (array, values from: \(Safety.riskKinds.sorted().joined(separator: ", "))), max_actions (integer), contact (string or null)."
        return try DecisionParser.subtask(try await ask(system: Prompts.planner + "\n" + fields, text: request, jpeg: nil))
    }

    func decide(_ c: DecisionContext) async throws -> Decision {
        let fields = "Fields: action (one of \(Schemas.actions.joined(separator: ", "))), element (integer or null), x (number or null), y (number or null), text (string or null), reason (string)."
        let json = try await ask(system: Prompts.actor + "\n" + fields, text: Prompts.step(c), jpeg: c.jpeg)
        return Decision(action: try DecisionParser.action(json, reading: c.reading),
                        reason: json["reason"] as? String ?? "", confidence: 1, source: "gemini")
    }

    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) {
        let json = try await ask(system: Prompts.verifier, text: Prompts.check(s, reading), jpeg: jpeg)
        return (json["done"] as? Bool ?? false, json["reason"] as? String ?? "")
    }

    func body(system: String, text: String, jpeg: Data?) -> [String: Any] {
        var parts: [[String: Any]] = []
        if let jpeg { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]]) }
        parts.append(["text": text])
        return [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]
    }

    private func ask(system: String, text: String, jpeg: Data?) async throws -> [String: Any] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIError("Bad Gemini model name.")
        }
        let started = Date()
        var text = text
        for attempt in 0...1 {  // an unreadable answer gets one more try
            let response = try await HTTP.postJSON(url, headers: ["x-goog-api-key": key], body: body(system: system, text: text, jpeg: jpeg),
                                                   timeout: 60, service: "Gemini")
            let candidate = (response["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            let answer = parts.compactMap { $0["text"] as? String }.joined()
            Log.event("ai.call", ["brain": "gemini", "model": model, "ms": Int(Date().timeIntervalSince(started) * 1000)])
            if let json = HTTP.jsonObject(in: answer) { return json }
            Log.info("Gemini answer not JSON (\(candidate?["finishReason"] as? String ?? "no answer")); attempt \(attempt + 1)")
            text += "\n\nYour previous reply was rejected: it was not JSON. Answer with JSON only."
        }
        throw AIError.notJSON
    }
}
