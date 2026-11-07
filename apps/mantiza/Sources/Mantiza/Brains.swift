import Foundation

/// Which keys the app has (from Secrets.swift, made by scripts/make_secrets.py).
enum Keys {
    static var openAI: String { Secrets.openAI }
    static var openRouter: String { Secrets.openRouter }
    static var gemini: String { Secrets.gemini }

    static var fastBrainRoute: String {
        if !openAI.isEmpty { return "OpenAI (direct)" }
        if !openRouter.isEmpty { return "OpenRouter" }
        return "missing key"
    }
}

enum BrainError: LocalizedError {
    case noKey(String)
    case http(Int, String)
    case badAnswer(String)

    var errorDescription: String? {
        switch self {
        case .noKey(let k): return "No \(k) key. Add it to keys.env and rebuild."
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .badAnswer(let s): return "Unexpected answer: \(s.prefix(200))"
        }
    }
}

private func postJSON(_ url: URL, headers: [String: String], body: [String: Any], timeout: Double = 20) async throws -> [String: Any] {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else { throw BrainError.http(code, String(decoding: data, as: UTF8.self)) }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BrainError.badAnswer(String(decoding: data, as: UTF8.self))
    }
    return json
}

// MARK: - Fast brain: OpenAI GPT-6 Luna Decisions

/// One typed choice with its confidence.
struct Choice {
    let value: String
    let confidence: Double
}

/// The fast brain answers multiple-choice questions about the screen in about 0.4 s and gives a
/// confidence for each answer. It writes no text. (Chosen after the brain bench, 2026-11-07.)
final class FastBrain {
    struct Question {
        let name: String
        let instructions: String
        let options: [(value: String, description: String)]
    }

    /// Asks all questions about one screenshot in one call.
    func ask(context: String, image: Data, questions: [Question]) async throws -> [String: Choice] {
        if !Keys.openAI.isEmpty { return try await askOpenAI(context: context, image: image, questions: questions) }
        if !Keys.openRouter.isEmpty {
            do {
                return try await askOpenRouter(context: context, image: image, questions: questions)
            } catch BrainError.http(let code, let body) where code == 502 && body.contains("refused to answer question") {
                // OpenRouter fails the whole call when the model declines one question
                // ("OpenAI refused to answer question \"target\""). Ask again without that one.
                let refused = questions.filter { body.contains("\\\"\($0.name)\\\"") || body.contains("\"\($0.name)\"") }
                let rest = questions.filter { q in !refused.contains { $0.name == q.name } }
                guard !refused.isEmpty, !rest.isEmpty else { throw BrainError.http(code, body) }
                return try await askOpenRouter(context: context, image: image, questions: rest)
            }
        }
        throw BrainError.noKey("OpenAI or OpenRouter")
    }

    /// OpenAI's own endpoint (POST /v1/decisions, model gpt-6-luna).
    private func askOpenAI(context: String, image: Data, questions: [Question]) async throws -> [String: Choice] {
        let body: [String: Any] = [
            "model": "gpt-6-luna",
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": context],
                ["type": "input_image", "image_url": "data:image/jpeg;base64," + image.base64EncodedString()],
            ]]],
            "questions": questions.map { q in
                ["type": "choice", "name": q.name, "instructions": q.instructions,
                 "choices": q.options.map { ["value": $0.value, "description": $0.description] }]
            },
        ]
        let json = try await postJSON(URL(string: "https://api.openai.com/v1/decisions")!,
                                      headers: ["Authorization": "Bearer " + Keys.openAI], body: body)
        guard let answers = json["answers"] as? [[String: Any]] else { throw BrainError.badAnswer("\(json)") }
        var out: [String: Choice] = [:]
        for a in answers {
            if let name = a["name"] as? String, let choice = a["choice"] as? String {
                out[name] = Choice(value: choice, confidence: (a["confidence"] as? Double) ?? 0)
            }
        }
        return out
    }

    /// The same model through OpenRouter's Decisions endpoint (until an OpenAI key is added).
    private func askOpenRouter(context: String, image: Data, questions: [Question]) async throws -> [String: Choice] {
        var qs: [String: Any] = [:]
        for q in questions {
            var criteria: [String: String] = [:]
            for o in q.options { criteria[o.value] = o.description }
            qs[q.name] = ["type": "choice", "instructions": q.instructions, "criteria": criteria]
        }
        let body: [String: Any] = [
            "model": "openai/gpt-6-luna-decisions",
            "state": [context, ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]]],
            "questions": qs,
        ]
        let json = try await postJSON(URL(string: "https://openrouter.ai/api/alpha/decisions")!,
                                      headers: ["Authorization": "Bearer " + Keys.openRouter,
                                                "X-OpenRouter-Title": "Mantiza"], body: body)
        guard let answers = json["answers"] as? [String: [String: Any]] else { throw BrainError.badAnswer("\(json)") }
        var out: [String: Choice] = [:]
        for (name, a) in answers {
            if let choice = a["choice"] as? String {
                out[name] = Choice(value: choice, confidence: (a["confidence"] as? Double) ?? 0)
            }
        }
        return out
    }
}

// MARK: - Big brain: Gemini 3.5 Flash-Lite (Google AI Studio key)

/// What the user asked for, turned into something the agent can do and check.
struct Subtask: Codable {
    var app: String?           // app to open, e.g. "WhatsApp"; nil if none
    var goal: String           // what must be true on screen at the end
    var text: String?          // exact text to type, taken from the request; nil if none
    var success_text: String?  // short text that will be on screen when done; nil if unsure
    var needs_approval: Bool?  // sends, posts, buys, deletes or calls something
    var max_steps: Int?
}

struct TapPoint {
    let x: Double  // 0…1 of the screenshot's width
    let y: Double  // 0…1 of its height
    let what: String
}

/// The big brain plans the task once, and finds things the fast brain can't (icons with no text,
/// or when it is unsure). Gemini 3.5 Flash-Lite: 98% right at about 1.2 s in the bench; thinking is
/// "minimal" by default.
final class BigBrain {
    private let model = "gemini-3.5-flash-lite"

    private func generate(parts: [[String: Any]]) async throws -> [String: Any] {
        guard !Keys.gemini.isEmpty else { throw BrainError.noKey("Gemini") }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]
        let json = try await postJSON(url, headers: ["x-goog-api-key": Keys.gemini], body: body)
        let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrainError.badAnswer(text)
        }
        return obj
    }

    /// Turns the user's request into a subtask (text only, once per task).
    func plan(_ request: String) async throws -> Subtask {
        let prompt = """
        You plan tasks for Mantiza, an assistant that operates an iPhone by tapping and typing.
        User request: "\(request)"

        Reply with only a JSON object:
        {"app": name of the iPhone app to open exactly as on the Home Screen (e.g. "WhatsApp", "Settings", "Clock"),
                or "Control Center" for quick switches that live there (flashlight, rotation lock, screen mirroring,
                calculator shortcut, timer shortcut, camera shortcut), or null,
         "goal": one sentence: what must be true on the screen when the task is done,
         "text": the exact text to type, copied from the request (never invent or translate), or null,
         "success_text": a short piece of text that will be visible on screen when done, or null if unsure,
         "needs_approval": true if the task sends, posts, buys, pays, deletes or calls anything, else false,
         "max_steps": number of taps it should take at most, between 4 and 15}
        """
        let obj = try await generate(parts: [["text": prompt]])
        let data = try JSONSerialization.data(withJSONObject: obj)
        var sub = try JSONDecoder().decode(Subtask.self, from: data)
        if sub.text?.isEmpty == true { sub.text = nil }
        if sub.app?.isEmpty == true { sub.app = nil }
        return sub
    }

    /// Finds where to tap next on a screenshot.
    func locate(image: Data, goal: String, history: [String]) async throws -> TapPoint {
        let done = history.isEmpty ? "nothing yet" : history.suffix(6).joined(separator: "; ")
        let prompt = """
        This is an iPhone screenshot. Goal: \(goal)
        Steps already done: \(done)
        Where should the user tap next? To turn a setting on or off, tap its switch (toggle), not its label.
        Give the point on a 0-1000 grid (0,0 top-left, 1000,1000 bottom-right).
        Reply with only JSON: {"x": <x>, "y": <y>, "what": "<short label of the thing to tap>"}
        """
        let obj = try await generate(parts: [
            ["text": prompt],
            ["inlineData": ["mimeType": "image/jpeg", "data": image.base64EncodedString()]],
        ])
        guard let x = (obj["x"] as? NSNumber)?.doubleValue, let y = (obj["y"] as? NSNumber)?.doubleValue else {
            throw BrainError.badAnswer("\(obj)")
        }
        return TapPoint(x: min(max(x / 1000, 0), 1), y: min(max(y / 1000, 0), 1), what: (obj["what"] as? String) ?? "?")
    }
}
