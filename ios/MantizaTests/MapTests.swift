import XCTest
@testable import Mantiza

/// A fake phone with titled list pages: tapping a row opens the page of that name, a swipe from the left edge
/// goes back.
@MainActor final class MapPhone {
    let board = MockBoard()
    let screen = StillScreen()
    var pages: [String: [String]]
    private(set) var stack: [String]
    private(set) var taps = 0

    init(_ pages: [String: [String]], start: String = "Settings") {
        self.pages = pages
        stack = [start]
        show()
        board.onCommand = { [weak self] c in
            guard let self else { return }
            if c.name == "tap", c.ints.count >= 2 {
                taps += 1
                let row = Int(floor((Double(c.ints[1]) / 32767 * 844 - 170) / 52))
                let rows = pages[stack.last!] ?? []
                if rows.indices.contains(row), pages[rows[row]] != nil { stack.append(rows[row]); show() }
            } else if c.name == "stroke", c.ints.count >= 4, Double(c.ints[0]) / 32767 < 0.05, stack.count > 1 {
                stack.removeLast()
                show()
            }
        }
    }

    var page: String { stack.last! }

    func show() { screen.show(DemoScreen.list(title: page, rows: pages[page] ?? [])) }

    func deps(_ brain: BigBrain, map: MapStore) -> AgentRunner.Deps {
        var d = AgentRunner.Deps(hands: Hands(channel: board.commands), screen: screen, big: brain, fast: nil,
                                 approve: { _ in true }, shouldStop: { false }, openURL: { _ in true })
        d.map = map
        return d
    }
}

/// Plans a fixed subtask (with a screen picked by the test) and decides from a closure, counting decisions.
final class MapBrain: BigBrain, @unchecked Sendable {
    var name = "map test"
    var plan: Subtask
    var decide: (ScreenReading) -> AgentAction
    private(set) var decides = 0
    private(set) var planned: [String] = []

    init(plan: Subtask, decide: @escaping (ScreenReading) -> AgentAction) {
        self.plan = plan
        self.decide = decide
    }

    func plan(_ request: String) async throws -> Subtask { planned.append(request); return plan }
    func decide(_ c: DecisionContext) async throws -> Decision {
        decides += 1
        return Decision(action: decide(c.reading), reason: "", confidence: 1, source: "claude")
    }
    func verify(_ s: Subtask, reading: ScreenReading, jpeg: Data?) async throws -> (done: Bool, reason: String) {
        (!reading.find("Model Name").isEmpty, "About is open")
    }
}

@MainActor final class MapTests: XCTestCase {
    static let pages: [String: [String]] = [
        "Settings": DemoScreen.rows,
        "General": ["About", "Software Update", "Storage"],
        "About": ["Name", "Software Version", "Model Name"],
    ]

    static let openAbout = Subtask(goal: "Open About in Settings", app: "Settings", verification: ["About is open"])

    func reading(_ texts: [String]) -> ScreenReading {
        ScreenReading(frameID: 1, elements: texts.enumerated().map { i, t in
            ScreenElement(id: i + 1, text: t, box: CGRect(x: 0.1, y: 0.1 + Double(i) * 0.06, width: 0.5, height: 0.03))
        })
    }

    func store() -> MapStore {
        MapStore(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    /// A first run, decided by the AI, that teaches the map the way to About.
    func learn(_ map: MapStore) async {
        let phone = MapPhone(Self.pages)
        _ = await AgentRunner().run("Open About", deps: phone.deps(MapBrain(plan: Self.openAbout, decide: Self.navigate), map: map))
    }

    /// The AI's way to About, one tap at a time.
    static func navigate(_ r: ScreenReading) -> AgentAction {
        if !r.find("Model Name").isEmpty { return .done("About is open") }
        if let e = r.find("About").first ?? r.find("General").first { return .tap(element: e.id, at: e.center) }
        return .blocked("lost")
    }

    func testLabelsLeaveOutTimesCountsAndSentences() {
        let r = reading(["9:41", "Settings", "3 new messages", "This is a long sentence that is not a label at all", "Wi-Fi", "Settings"])
        XCTAssertEqual(PhoneMap.labels(r), ["settings", "wi-fi"])
        XCTAssertEqual(PhoneMap.title(r), "settings")
    }

    func testListContentsDoNotSplitAScreen() throws {
        var map = PhoneMap()
        let tabs = ["Chats", "Updates", "Communities", "Calls", "You"]
        let first = try XCTUnwrap(map.observe(reading(tabs + ["Asha", "Ben"]), app: "whatsapp"))
        XCTAssertEqual(map.observe(reading(tabs + ["Chen", "Dana"]), app: "whatsapp"), first)
        XCTAssertEqual(map.observe(reading(tabs + ["Eli", "Farah"]), app: "whatsapp"), first)
        XCTAssertEqual(map.screen(first)?.anchors, Set(tabs.map { $0.lowercased() }))  // the names dropped out
        XCTAssertEqual(map.screens.count, 1)

        // A different page, or the same page in another app, is a new screen.
        XCTAssertNotEqual(map.observe(reading(["Settings", "Account", "Privacy", "Notifications"]), app: "whatsapp"), first)
        XCTAssertNotEqual(map.observe(reading(tabs), app: "signal"), first)
    }

    func testRedesignKeepsTheScreenWhenTheTitleStays() throws {
        var map = PhoneMap()
        let id = try XCTUnwrap(map.observe(reading(["General", "About", "Software Update", "Storage", "Fonts"]), app: "settings"))
        XCTAssertEqual(map.observe(reading(["General", "About", "Software Update", "Keyboard", "Language"]), app: "settings"), id)
    }

    func testRouteTakesTheCheapestPathAndDropsFailingEdges() throws {
        var map = PhoneMap()
        let a = try XCTUnwrap(map.observe(reading(["Alpha", "One", "Two"]), app: "x"))
        let b = try XCTUnwrap(map.observe(reading(["Bravo", "Three", "Four"]), app: "x"))
        let c = try XCTUnwrap(map.observe(reading(["Charlie", "Five", "Six"]), app: "x"))
        map.record(from: a, RecordedAction(kind: "tap", target: "Bravo"), to: b)
        map.record(from: b, RecordedAction(kind: "tap", target: "Charlie"), to: c)
        map.record(from: a, RecordedAction(kind: "tap", target: "Shortcut"), to: c)
        map.record(from: a, RecordedAction(kind: "tap", target: nil, point: .zero), to: c)  // icon taps are not walked
        XCTAssertEqual(map.edges.count, 3)
        XCTAssertEqual(map.route(from: a, to: c)?.map(\.action.target), ["Shortcut"])
        XCTAssertEqual(map.route(from: a, to: a)?.count, 0)
        XCTAssertNil(map.route(from: c, to: a))

        let shortcut = try XCTUnwrap(map.route(from: a, to: c)?.first)
        map.failed(shortcut)
        XCTAssertEqual(map.route(from: a, to: c)?.map(\.action.target), ["Bravo", "Charlie"])  // 3 > 1 + 1
        map.failed(shortcut)
        map.failed(shortcut)
        XCTAssertEqual(map.edges.count, 2)
    }

    func testForgetsScreensNotSeenForMonths() throws {
        var map = PhoneMap()
        let old = Date().addingTimeInterval(-100 * 86_400)
        let a = try XCTUnwrap(map.observe(reading(["Alpha", "One"]), app: "x", at: old))
        let b = try XCTUnwrap(map.observe(reading(["Bravo", "Two"]), app: "x"))
        map.record(from: a, RecordedAction(kind: "tap", target: "Bravo"), to: b)
        map.prune()
        XCTAssertEqual(map.screens.map(\.id), [b])
        XCTAssertTrue(map.edges.isEmpty)
    }

    func testARunTeachesTheMapAndTheNextOneWalksItWithoutTheAI() async throws {
        let map = store()
        let first = MapBrain(plan: Self.openAbout, decide: Self.navigate)
        let learner = MapPhone(Self.pages)  // the phone must outlive the run: the stick link holds it weakly
        let learned = await AgentRunner().run("Open About", deps: learner.deps(first, map: map))
        XCTAssertEqual(learned, .done("About is open"))
        XCTAssertEqual(first.decides, 3)  // General, About, done
        XCTAssertEqual(Set(map.map.screens.map(\.title)), ["settings", "general", "about"])
        XCTAssertEqual(map.map.edges.map { $0.action.target }, ["General", "About"])
        let about = try XCTUnwrap(map.map.screens.first { $0.title == "about" })
        let saved = MapStore(file: map.file).map  // persisted (dates to the second)
        XCTAssertEqual(saved.screens.map(\.counts), map.map.screens.map(\.counts))
        XCTAssertEqual(saved.edges.map(\.action), map.map.edges.map(\.action))

        // The planner sees the known screens and names one; the walk gets there with no decisions.
        var plan = Self.openAbout
        plan.screen = about.id
        let second = MapBrain(plan: plan) { r in r.find("Model Name").isEmpty ? .blocked("asked to navigate") : .done("About is open") }
        let phone = MapPhone(Self.pages)
        let runner = AgentRunner()
        let walked = await runner.run("Open About", deps: phone.deps(second, map: map))
        XCTAssertEqual(walked, .done("About is open"))
        XCTAssertTrue(second.planned[0].contains("\(about.id) | settings | about"))
        XCTAssertEqual(second.decides, 1)  // only "done"
        XCTAssertEqual(phone.taps, 2)
        XCTAssertEqual(runner.steps.filter { $0.source == "map" }.compactMap(\.recorded).map(\.target), ["General", "About"])
        XCTAssertEqual(map.map.edges.map(\.ok), [2, 2])
    }

    func testAMovedRowIsFoundByItsLabel() async throws {
        let map = store()
        await learn(map)
        var plan = Self.openAbout
        plan.screen = try XCTUnwrap(map.map.screens.first { $0.title == "about" }).id

        // An update added two rows above General.
        var moved = Self.pages
        moved["Settings"] = ["Wi-Fi", "Bluetooth"] + DemoScreen.rows
        let brain = MapBrain(plan: plan) { r in r.find("Model Name").isEmpty ? .blocked("asked to navigate") : .done("About is open") }
        let phone = MapPhone(moved)
        let outcome = await AgentRunner().run("Open About", deps: phone.deps(brain, map: map))
        XCTAssertEqual(outcome, .done("About is open"))
        XCTAssertEqual(brain.decides, 1)
    }

    func testAChangedScreenHandsOverToTheAIAndCountsAgainstTheEdge() async throws {
        let map = store()
        await learn(map)
        var plan = Self.openAbout
        plan.screen = try XCTUnwrap(map.map.screens.first { $0.title == "about" }).id

        // General now leads to a page the map has never seen.
        var changed = Self.pages
        changed["General"] = ["Sign In Required", "Continue", "Cancel"]
        let brain = MapBrain(plan: plan) { _ in .blocked("needs the user") }
        let phone = MapPhone(changed)
        let outcome = await AgentRunner().run("Open About", deps: phone.deps(brain, map: map))
        XCTAssertEqual(outcome, .blocked("needs the user"))
        XCTAssertEqual(brain.decides, 1)
        XCTAssertEqual(map.map.edges.first { $0.action.target == "General" }?.failed, 1)
    }

    func testPlannerGetsKnownScreensOnlyWhenThereAreAny() {
        XCTAssertEqual(Prompts.planRequest("Open About", screens: ""), "Open About")
        XCTAssertTrue(Prompts.planRequest("Open About", screens: "s1 | settings | general | about").hasPrefix("Request: Open About\n\nKnown screens"))
        XCTAssertTrue((Schemas.plan["required"] as? [String] ?? []).contains("screen"))
    }
}
