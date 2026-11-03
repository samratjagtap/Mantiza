import XCTest
@testable import Mantiza

final class AITests: XCTestCase {
    let reading = ScreenReading(frameID: 1, elements: [
        ScreenElement(id: 1, text: "Azad", box: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.03)),
        ScreenElement(id: 2, text: "Send", box: CGRect(x: 0.8, y: 0.9, width: 0.1, height: 0.03)),
    ])

    func testClaudeRequestBody() throws {
        let brain = ClaudeBrain(key: "k")
        let body = brain.body(system: "sys", content: ClaudeBrain.content("step", Data([1, 2])), schema: Schemas.action, maxTokens: 100)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
        let system = try XCTUnwrap((body["system"] as? [[String: Any]])?.first)
        XCTAssertNotNil(system["cache_control"])
        let content = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
        XCTAssertNil(ClaudeBrain(key: "k", model: "claude-haiku-5-5").body(system: "", content: [], schema: [:], maxTokens: 1)["fallbacks"])
    }

    func testClaudeAnswerParsing() throws {
        let ok: [String: Any] = ["stop_reason": "end_turn", "content": [
            ["type": "thinking", "thinking": ""],
            ["type": "text", "text": #"{"action":"tap","element":1,"x":null,"y":null,"text":null,"reason":"open chat"}"#],
        ]]
        let json = try ClaudeBrain.answer(ok)
        guard case let .tap(element, at) = try DecisionParser.action(json, reading: reading) else { return XCTFail() }
        XCTAssertEqual(element, 1)
        XCTAssertEqual(at.y, 0.215, accuracy: 1e-9)
        XCTAssertThrowsError(try ClaudeBrain.answer(["stop_reason": "refusal", "content": []]))
        XCTAssertThrowsError(try ClaudeBrain.answer(["stop_reason": "end_turn", "content": [["type": "text", "text": "hi"]]]))
    }

    func testDecisionParserCoordinatesAndErrors() throws {
        XCTAssertEqual(try DecisionParser.action(["action": "tap", "element": NSNull(), "x": 500, "y": 250], reading: reading),
                       .tap(element: nil, at: CGPoint(x: 0.5, y: 0.25)))
        XCTAssertThrowsError(try DecisionParser.action(["action": "tap", "element": 99], reading: reading))
        XCTAssertThrowsError(try DecisionParser.action(["action": "type", "text": ""], reading: reading))
        XCTAssertThrowsError(try DecisionParser.action(["action": "dance"], reading: reading))
        XCTAssertEqual(try DecisionParser.action(["action": "ask_user", "text": "Which size?"], reading: reading), .askUser("Which size?"))
        XCTAssertThrowsError(try DecisionParser.action(["action": "ask_user"], reading: reading))
        XCTAssertEqual(try DecisionParser.action(["action": "open_app", "text": "Maps"], reading: reading), .openApp("Maps"))
    }

    func testPlanParsingClampsAndFiltersRisks() throws {
        let s = try DecisionParser.subtask(["goal": "Reply to Azad", "app": "Messages", "inputs": ["I'm coming"],
                                            "verification": ["Message sent"], "allowed_risks": ["SEND", "hack"], "max_actions": 99])
        XCTAssertEqual(s.allowedRisks, ["send"])
        XCTAssertEqual(s.maxActions, 30)
        XCTAssertNil(try DecisionParser.subtask(["goal": "x", "app": NSNull(), "inputs": [], "verification": [],
                                                 "allowed_risks": [], "max_actions": 5]).app)
    }

    func testGeminiBody() {
        let body = GeminiBrain(key: "k").body(system: "s", text: "t", jpeg: Data([1]))
        let parts = ((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual((body["generationConfig"] as? [String: Any])?["responseMimeType"] as? String, "application/json")
    }

    // MARK: Jev

    private var context: DecisionContext {
        DecisionContext(subtask: Subtask(goal: "Reply to Azad", app: "Messages", inputs: ["I'm coming"],
                                         verification: ["The message appears"]), reading: reading, jpeg: nil, history: [])
    }

    func testJevBody() throws {
        let body = SystemOnePicker.body(context, elements: reading.elements)
        XCTAssertEqual(body["model"] as? String, "jev-1.14.0")
        let q = try XCTUnwrap(body["questions"] as? [String: Any])
        XCTAssertEqual(Set(q.keys), ["operation", "tap_target", "text_input", "verify_0"])
        let targets = try XCTUnwrap((q["tap_target"] as? [String: Any])?["criteria"] as? [String: String])
        XCTAssertEqual(Set(targets.keys), ["e1", "e2", "NONE"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    private func choice(_ c: String, _ p: [String: Double], confidence: Double) -> [String: Any] {
        ["type": "choice", "choice": c, "confidence": confidence, "probabilities": p]
    }

    func testJevConfidentTap() {
        let answers: [String: Any] = [
            "operation": choice("TAP", ["TAP": 0.9, "WAIT": 0.1], confidence: 0.85),
            "tap_target": choice("e1", ["e1": 0.8, "e2": 0.1, "NONE": 0.1], confidence: 0.7),
        ]
        XCTAssertEqual(SystemOnePicker.interpret(answers, context: context, elements: reading.elements)?.action,
                       .tap(element: 1, at: reading.elements[0].center))
    }

    func testJevUnsureGoesToBigBrain() {
        let lowMargin: [String: Any] = ["operation": choice("TAP", ["TAP": 0.5, "BACK": 0.45, "WAIT": 0.05], confidence: 0.7)]
        XCTAssertNil(SystemOnePicker.interpret(lowMargin, context: context, elements: reading.elements))
        let lowConfidence: [String: Any] = ["operation": choice("TAP", ["TAP": 0.6, "BACK": 0.4], confidence: 0.3)]
        XCTAssertNil(SystemOnePicker.interpret(lowConfidence, context: context, elements: reading.elements))
        let needsAgent: [String: Any] = ["operation": choice("NEEDS_AGENT", ["NEEDS_AGENT": 1], confidence: 1)]
        XCTAssertNil(SystemOnePicker.interpret(needsAgent, context: context, elements: reading.elements))
        let unknownTarget: [String: Any] = [
            "operation": choice("TAP", ["TAP": 1], confidence: 1),
            "tap_target": choice("e9", ["e9": 1], confidence: 1),
        ]
        XCTAssertNil(SystemOnePicker.interpret(unknownTarget, context: context, elements: reading.elements))
    }

    func testJevTypesOnlyOfferedInputAndDoneNeedsChecks() {
        let type: [String: Any] = [
            "operation": choice("TYPE_TEXT", ["TYPE_TEXT": 1], confidence: 1),
            "text_input": choice("t0", ["t0": 0.95, "NONE": 0.05], confidence: 0.9),
        ]
        XCTAssertEqual(SystemOnePicker.interpret(type, context: context, elements: [])?.action, .type("I'm coming"))
        var done: [String: Any] = ["operation": choice("DONE", ["DONE": 1], confidence: 1), "verify_0": ["type": "noul", "noul": 0.4]]
        XCTAssertNil(SystemOnePicker.interpret(done, context: context, elements: []))
        done["verify_0"] = ["type": "noul", "noul": 0.95]
        XCTAssertEqual(SystemOnePicker.interpret(done, context: context, elements: [])?.action.name, "done")
    }

    func testLayaService() throws {
        let laya = SystemOnePicker.Service.laya(try XCTUnwrap(URL(string: "http://10.0.0.243:8000")))
        XCTAssertEqual(laya.url.absoluteString, "http://10.0.0.243:8000/v1/systemone")
        let body = SystemOnePicker.body(context, elements: reading.elements, model: laya.model)
        XCTAssertEqual(body["model"] as? String, "mantiza")
        XCTAssertLessThan(laya.maxElements, 100)  // the server caps a choice at 100 options, NONE included
    }

    func testLayaGateIsStricterAndTagsSteps() throws {
        let laya = SystemOnePicker.Service.laya(try XCTUnwrap(URL(string: "http://mac.local:8000")))
        let jevSure: [String: Any] = [
            "operation": choice("TAP", ["TAP": 0.7, "WAIT": 0.3], confidence: 0.7),
            "tap_target": choice("e1", ["e1": 0.8, "e2": 0.1, "NONE": 0.1], confidence: 0.8),
        ]
        XCTAssertNotNil(SystemOnePicker.interpret(jevSure, context: context, elements: reading.elements, service: .jev))
        XCTAssertNil(SystemOnePicker.interpret(jevSure, context: context, elements: reading.elements, service: laya))
        let sure: [String: Any] = [
            "operation": choice("TAP", ["TAP": 0.95, "WAIT": 0.05], confidence: 0.95),
            "tap_target": choice("e2", ["e2": 0.9, "e1": 0.05, "NONE": 0.05], confidence: 0.9),
        ]
        let decision = SystemOnePicker.interpret(sure, context: context, elements: reading.elements, service: laya)
        XCTAssertEqual(decision?.source, "laya")
        XCTAssertEqual(decision?.action, .tap(element: 2, at: reading.elements[1].center))
    }

    // MARK: Laya training rows

    func testTrainingLabelsFromBigBrainDecisions() {
        let e = reading.elements
        XCTAssertEqual(TrainingLog.expected(.tap(element: 2, at: .zero), elements: e, inputs: [], checks: 1, verified: nil) as? [String: String],
                       ["operation": "TAP", "tap_target": "e2"])
        XCTAssertEqual(TrainingLog.expected(.tap(element: nil, at: .zero), elements: e, inputs: [], checks: 1, verified: nil) as? [String: String],
                       ["operation": "NEEDS_AGENT"])
        XCTAssertEqual(TrainingLog.expected(.type("I'm coming"), elements: e, inputs: ["I'm coming"], checks: 1, verified: nil) as? [String: String],
                       ["operation": "TYPE_TEXT", "text_input": "t0"])
        XCTAssertTrue(TrainingLog.expected(.done("ok"), elements: e, inputs: [], checks: 1, verified: false).isEmpty)
        let done = TrainingLog.expected(.done("ok"), elements: e, inputs: [], checks: 2, verified: true)
        XCTAssertEqual(done["operation"] as? String, "DONE")
        XCTAssertEqual(done["verify_1"] as? Bool, true)
    }

    func testTrainingRowIsLayaJSONL() throws {
        let row = try XCTUnwrap(TrainingLog.row(context, decision: .tap(element: 1, at: .zero), step: 3))
        XCTAssertNil(row["model"])
        XCTAssertNotNil(row["state"])
        let questions = try XCTUnwrap(row["questions"] as? [String: Any])
        let expected = try XCTUnwrap(row["expected"] as? [String: Any])
        XCTAssertTrue(Set(expected.keys).isSubset(of: Set(questions.keys)))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: row))
    }

    // MARK: Safety

    func testRiskyButtonsAreHiddenUnlessAllowed() {
        XCTAssertEqual(Safety.risk(of: reading.elements[1]), "send")
        XCTAssertNil(Safety.risk(of: ScreenElement(id: 3, text: "Can you send me the file tomorrow?", box: .zero)))
        XCTAssertEqual(Safety.filter(reading, allowed: []).hidden, [2])
        XCTAssertEqual(Safety.filter(reading, allowed: ["send"]).hidden, [])
        XCTAssertEqual(Safety.risk(of: ScreenElement(id: 4, text: "Buy Now", box: .zero)), "purchase")
    }

    func testStopScreensAndSecrets() {
        let pay = ScreenReading(frameID: 1, elements: [ScreenElement(id: 1, text: "Enter UPI PIN", box: .zero)])
        XCTAssertNotNil(Safety.stopReason(pay))
        XCTAssertNil(Safety.stopReason(reading))
        XCTAssertTrue(Safety.looksSecret("4321"))
        XCTAssertTrue(Safety.looksSecret("4111 1111 1111 1111"))
        XCTAssertFalse(Safety.looksSecret("I'm coming"))
        XCTAssertFalse(Safety.looksSecret("Meet at 5"))
    }
}
