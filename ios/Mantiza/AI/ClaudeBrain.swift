import Foundation

/// Claude through the Messages API over HTTPS (there is no Swift SDK). Each call is one stateless request:
/// the frozen system prompt is cached, the step text and screenshot follow it, and the answer is constrained
/// to a JSON schema with structured outputs.
struct ClaudeBrain: BigBrain {
    static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    static let defaultModel = "claude-opus-5-5"

    let key: String
    var model = ClaudeBrain.defaultModel
    /// Effort per call: planning and acting are routine; raise it for hard apps.
    var effort = "low"
    var name: String { "Claude (\(model))" }

    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!

    func plan(_ request: String) async throws -> Subtask {
        let json = try await ask(system: Prompts.planner, content: [["type": "text", "text": request]],
                                 schema: Schemas.plan, maxTokens: 4000)
        return try DecisionParser.subtask(json)
    }

    func decide(_ c: DecisionContext) async throws -> Decision {
        let json = try await ask(system: Prompts.actor, content: Self.content(Prompts.step(c), c.jpeg),
                                 schema: Schemas.action, maxTokens: 4000)
        return Decision(action: try DecisionParser.action(json, reading: c.reading),
                        reason: json["reason"] as? String ?? "", confidence: 1, source: "claude")
    }

    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) {
        let json = try await ask(system: Prompts.verifier, content: Self.content(Prompts.check(s, reading), jpeg),
                                 schema: Schemas.verdict, maxTokens: 2000)
        return (json["done"] as? Bool ?? false, json["reason"] as? String ?? "")
    }

    static func content(_ text: String, _ jpeg: Data?) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if let jpeg {
            blocks.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                       "data": jpeg.base64EncodedString()]])
        }
        blocks.append(["type": "text", "text": text])
        return blocks
    }

    /// The request body (separate so tests can check it without a network call).
    func body(system: String, content: [[String: Any]], schema: [String: Any], maxTokens: Int) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": content]],
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schema]],
        ]
        if Self.fallbackModels.contains(model) { body["fallbacks"] = "default" }
        return body
    }

    /// Models whose safety classifiers may decline; the API re-runs a declined request on a fallback model.
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    private func ask(system: String, content: [[String: Any]], schema: [String: Any], maxTokens: Int) async throws -> [String: Any] {
        var headers = ["x-api-key": key, "anthropic-version": "2026-10-21"]
        if Self.fallbackModels.contains(model) { headers["anthropic-beta"] = "server-side-fallback-2026-07-01" }
        let started = Date()
        let response = try await HTTP.postJSON(Self.url, headers: headers,
                                               body: body(system: system, content: content, schema: schema, maxTokens: maxTokens),
                                               timeout: 60, service: "Claude")
        let result = try Self.answer(response)
        let usage = response["usage"] as? [String: Any] ?? [:]
        Log.event("ai.call", ["brain": "claude", "model": response["model"] as? String ?? model,
                              "ms": Int(Date().timeIntervalSince(started) * 1000),
                              "in": usage["input_tokens"] as? Int ?? 0, "out": usage["output_tokens"] as? Int ?? 0,
                              "cached": usage["cache_read_input_tokens"] as? Int ?? 0])
        return result
    }

    /// The JSON answer from a Messages API response; refusals and cut-off answers are errors.
    static func answer(_ response: [String: Any]) throws -> [String: Any] {
        switch response["stop_reason"] as? String {
        case "refusal": throw AIError("Claude declined this step.")
        case "max_tokens": throw AIError("Claude's answer was cut off.")
        default: break
        }
        let blocks = response["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let json = HTTP.jsonObject(in: text) else { throw AIError("Claude did not answer with JSON.") }
        return json
    }
}

/// JSON schemas for structured outputs (every object closed, every field required; null where optional).
enum Schemas {
    static func nullable(_ type: String) -> [String: Any] { ["anyOf": [["type": type], ["type": "null"]]] }

    static let actions = ["tap", "type", "scroll_down", "scroll_up", "back", "home", "open_app", "ask_user", "wait", "done", "blocked"]

    static let action: [String: Any] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": actions],
            "element": nullable("integer"),
            "x": nullable("number"),
            "y": nullable("number"),
            "text": nullable("string"),
            "reason": ["type": "string"],
        ],
        "required": ["action", "element", "x", "y", "text", "reason"],
        "additionalProperties": false,
    ]

    static let plan: [String: Any] = [
        "type": "object",
        "properties": [
            "goal": ["type": "string"],
            "app": nullable("string"),
            "inputs": ["type": "array", "items": ["type": "string"]],
            "verification": ["type": "array", "items": ["type": "string"]],
            "allowed_risks": ["type": "array", "items": ["type": "string", "enum": Array(Safety.riskKinds).sorted()]],
            "max_actions": ["type": "integer"],
            "contact": nullable("string"),
        ],
        "required": ["goal", "app", "inputs", "verification", "allowed_risks", "max_actions", "contact"],
        "additionalProperties": false,
    ]

    static let verdict: [String: Any] = [
        "type": "object",
        "properties": ["done": ["type": "boolean"], "reason": ["type": "string"]],
        "required": ["done", "reason"],
        "additionalProperties": false,
    ]
}
