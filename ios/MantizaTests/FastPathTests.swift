import XCTest
@testable import Mantiza

final class FastPathTests: XCTestCase {
    let azad = FastPath.Match(name: "Azad Jagtap", phones: ["+1 (510) 555-0100"])

    func testMessagesToOneContactPrefillsText() throws {
        let s = Subtask(goal: "Tell Azad I'm coming", app: "Messages", inputs: ["I'm coming & on my way?"], contact: "Azad")
        let (url, note) = try XCTUnwrap(FastPath.url(for: s, contacts: [azad]))
        XCTAssertEqual(url.absoluteString, "sms:+15105550100&body=I'm%20coming%20%26%20on%20my%20way%3F")
        XCTAssertTrue(note.contains("Azad Jagtap"))
    }

    func testAmbiguousOrMissingContactFallsBackToTapping() {
        let s = Subtask(goal: "x", app: "Messages", inputs: ["hi"], contact: "Sam")
        XCTAssertNil(FastPath.url(for: s, contacts: []))
        XCTAssertNil(FastPath.url(for: s, contacts: [azad, azad]))
        XCTAssertNil(FastPath.url(for: Subtask(goal: "x", app: "Messages", inputs: ["hi"]), contacts: [azad]))
    }

    func testMapsAndShortcuts() {
        XCTAssertEqual(FastPath.url(for: Subtask(goal: "x", app: "Maps", inputs: ["Blue Bottle Coffee"]), contacts: [])?.url.absoluteString,
                       "maps://?q=Blue%20Bottle%20Coffee")
        XCTAssertEqual(FastPath.url(for: Subtask(goal: "x", app: "Shortcuts", inputs: ["Good Night"]), contacts: [])?.url.absoluteString,
                       "shortcuts://run-shortcut?name=Good%20Night")
        XCTAssertNil(FastPath.url(for: Subtask(goal: "x", app: "Notes", inputs: ["a"]), contacts: []))
    }

    func testPlanSchemaHasContact() throws {
        let s = try DecisionParser.subtask(["goal": "g", "app": "Messages", "inputs": ["hi"], "verification": [],
                                            "allowed_risks": ["send"], "max_actions": 8, "contact": "Azad"])
        XCTAssertEqual(s.contact, "Azad")
        XCTAssertTrue((Schemas.plan["required"] as? [String] ?? []).contains("contact"))
    }
}
