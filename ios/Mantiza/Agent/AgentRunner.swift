import CoreGraphics
import Foundation
import Observation

/// Runs one task: plan, open the app, then look -> decide -> act until the checks pass, with the safety gate,
/// a freshness check before each tap, stuck detection and no blind retries.
@MainActor @Observable final class AgentRunner {
    enum Outcome: Equatable {
        case done(String)
        case blocked(String)
        case failed(String)
        case stopped

        var summary: String {
            switch self {
            case let .done(why): return "Done. \(why)"
            case let .blocked(why): return "Stopped: \(why)"
            case let .failed(why): return "Failed: \(why)"
            case .stopped: return "Stopped by you."
            }
        }
    }

    struct Step: Identifiable, Equatable, Codable {
        var id: Int
        var text: String
        /// Deciding (fast + big brain).
        var ms: Int
        var captureMs = 0
        var ocrMs = 0
        var actMs = 0
        var source = ""
        /// What was done, for learned workflows.
        var recorded: RecordedAction?
    }

    /// What the runner needs from the app (closures so tests can fake each part).
    struct Deps {
        var hands: Hands
        var screen: ScreenSource
        var big: BigBrain
        var fast: FastBrain?
        /// Ask the user to approve a risky action (on the stick); true = approved.
        var approve: (String) async -> Bool
        var shouldStop: () -> Bool
        /// Open an app by URL while Mantiza is in front; false if not possible.
        var openURL: (URL) async -> Bool
        /// Step n of at most m, and what it is doing (Live Activity).
        var progress: (Int, Int, String) -> Void = { _, _, _ in }
        /// Contacts matching a name (fast path); empty when not allowed.
        var findContacts: (String) async -> [FastPath.Match] = { _ in [] }
        /// Ask the user a question (on the stick, answered by voice); nil when nobody answered.
        var askUser: (String) async -> String? = { _ in nil }
    }

    private(set) var subtask: Subtask?
    private(set) var steps: [Step] = []
    private(set) var status = ""
    private(set) var outcome: Outcome?
    var running: Bool { outcome == nil && !status.isEmpty }

    @ObservationIgnored private var deps: Deps!
    @ObservationIgnored private var history: [String] = []
    /// Big-brain decisions as Laya training rows (TrainingLog), saved by the app when the run ends.
    @ObservationIgnored private(set) var training: [[String: Any]] = []

    /// Plan the request with the big brain, then run it.
    func run(_ request: String, deps: Deps, prepare: () async throws -> Void = {}) async -> Outcome {
        self.deps = deps
        steps = []; outcome = nil; history = []; training = []
        say("Planning")
        Log.event("run.start", ["request": request])
        do {
            let plan = try await deps.big.plan(request)
            subtask = plan
            note("Plan: \(plan.goal) in \(plan.app ?? "any app"); \(plan.verification.count) checks", ms: 0)
            try await prepare()  // e.g. start screen sharing while Mantiza is still in front
            return finish(try await execute(plan))
        } catch is CancellationError {
            return finish(.stopped)
        } catch {
            return finish(.failed(error.localizedDescription))
        }
    }

    /// Run an already planned subtask (tests and replayed workflows).
    func run(_ plan: Subtask, deps: Deps) async -> Outcome {
        self.deps = deps
        steps = []; outcome = nil; history = []; training = []; subtask = plan
        do { return finish(try await execute(plan)) } catch is CancellationError { return finish(.stopped) } catch {
            return finish(.failed(error.localizedDescription))
        }
    }

    /// Replay a learned workflow: repeat its recorded steps by finding each target's text on screen, without asking
    /// the AI; when the screen does not match (or the check fails at the end), the normal AI loop takes over.
    func replay(_ w: Workflow, deps: Deps) async -> Outcome {
        self.deps = deps
        steps = []; outcome = nil; history = []; training = []; subtask = w.subtask
        say("Replaying \(w.name)")
        Log.event("run.start", ["request": w.request, "workflow": w.id.uuidString])
        do {
            try await startApp(w.subtask)
            var lastAction = Date()
            for (i, step) in w.steps.enumerated() {
                if deps.shouldStop() { return finish(.stopped) }
                deps.progress(i + 1, w.steps.count, "Replaying step \(i + 1)")
                let started = Date()
                let frame = try await deps.screen.settled(after: lastAction)
                let reading = try await OCR.read(frame)
                if let why = Safety.stopReason(reading) { return finish(.blocked(why)) }
                guard let done = try await replayStep(step, reading: reading, subtask: w.subtask) else {
                    note("screen differs from the saved workflow at step \(i + 1); asking the AI", ms: 0, source: "replay")
                    return finish(try await loop(w.subtask))
                }
                if !done { return finish(.blocked("You declined a step of the workflow.")) }
                note("replay: \(step.kind) \(step.target ?? step.text ?? "")", ms: Self.ms(started), source: "replay",
                     recorded: step)
                history.append("replayed \(step.kind) \(step.target ?? step.text ?? "")")
                lastAction = Date()
            }
            let frame = try await deps.screen.settled(after: lastAction)
            let reading = try await OCR.read(frame)
            let check = try await deps.big.verify(w.subtask, reading: reading, jpeg: frame.jpeg())
            note("check: \(check.done ? "passed" : "failed") \(check.reason)", ms: 0, source: deps.big.name.lowercased().hasPrefix("claude") ? "claude" : "gemini")
            if check.done { return finish(.done(check.reason)) }
            return finish(try await loop(w.subtask))
        } catch is CancellationError {
            return finish(.stopped)
        } catch {
            return finish(.failed(error.localizedDescription))
        }
    }

    /// One recorded step on the current screen. nil = the screen does not match; false = the user declined.
    private func replayStep(_ step: RecordedAction, reading: ScreenReading, subtask s: Subtask) async throws -> Bool? {
        let d = deps!
        switch step.kind {
        case "tap":
            guard let label = step.target else { return nil }  // icons need the AI to find them again
            let near = step.point ?? CGPoint(x: 0.5, y: 0.5)
            guard let e = reading.find(label).min(by: { distance($0.center, near) < distance($1.center, near) }) else { return nil }
            if let kind = Safety.risk(of: e) {
                guard s.allowedRisks.contains(kind) else { return nil }
                guard await d.approve("\(kind.capitalized): tap \(e.text)?") else { return false }
            }
            try await act { try await d.hands.tap(e.center) }
        case "type":
            guard let text = step.text, s.inputs.contains(text), !Safety.looksSecret(text) else { return nil }
            try await act { try await d.hands.type(text) }
        case "scroll_down", "scroll_up":
            try await act { try await d.hands.scroll(down: step.kind == "scroll_down") }
        case "back":
            try await act { try await d.hands.swipe(from: CGPoint(x: 0.01, y: 0.5), to: CGPoint(x: 0.7, y: 0.5)) }
        case "home":
            try await act { try await d.hands.home() }
        case "open_app":
            guard let name = step.text else { return nil }
            try await openApp(name)
        default:
            return nil
        }
        return true
    }

    private func finish(_ o: Outcome) -> Outcome {
        outcome = o
        status = o.summary
        let state: BoardCommand.UiState = { if case .done = o { return .done }; return .error }()
        Task { [deps] in _ = try? await deps?.hands.channel.send(.ui(state, text: String(o.summary.prefix(60)))) }
        Log.event("run.end", ["outcome": o.summary, "steps": steps.count])
        return o
    }

    private func say(_ text: String) { status = text }

    nonisolated static func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

    private func note(_ text: String, ms: Int, capture: Int = 0, ocr: Int = 0, act: Int = 0, source: String = "",
                      recorded: RecordedAction? = nil) {
        steps.append(Step(id: steps.count + 1, text: text, ms: ms, captureMs: capture, ocrMs: ocr, actMs: act,
                          source: source, recorded: recorded))
        Log.event("run.step", ["n": steps.count, "text": text, "decide": ms, "capture": capture, "ocr": ocr, "act": act,
                               "source": source])
    }

    private func execute(_ s: Subtask) async throws -> Outcome {
        try await startApp(s)
        return try await loop(s)
    }

    /// Open the task's app: by fast path when it applies, else by URL scheme or Home Screen icon.
    private func startApp(_ s: Subtask) async throws {
        let d = deps!
        let contacts = if let name = s.contact { await d.findContacts(name) } else { [FastPath.Match]() }
        if let fast = FastPath.url(for: s, contacts: contacts), await d.openURL(fast.url) {
            note(fast.note, ms: 0, source: "fast path")
            history.append(fast.note.lowercased())
            try await Task.sleep(for: .seconds(1.2))
        } else if let app = s.app {
            say("Opening \(app)")
            try await openApp(app)
            history.append("opened \(app) (it may still be loading)")
        }
    }

    /// Look -> decide -> act until the checks pass.
    private func loop(_ subtask: Subtask) async throws -> Outcome {
        var s = subtask  // the user's answers to questions become inputs
        let d = deps!
        var lastAction = Date()
        var before: Frame?           // the frame the last screen-changing action was taken on
        var lastSignature = ""       // action + target on that frame, to refuse a blind repeat
        var noChange = 0, stale = 0, actions = 0
        while actions < s.maxActions {
            if d.shouldStop() { return .stopped }
            try Task.checkCancellation()
            let started = Date()
            let frame = try await d.screen.settled(after: lastAction)
            let captureMs = Self.ms(started)
            if let previous = before {
                let changed = ScreenDiff.changed(previous.image, frame.image)
                noChange = changed ? 0 : noChange + 1
                history[history.count - 1] += changed ? " -> screen changed" : " -> no change"
                if noChange >= 3 { return .blocked("The screen stopped responding to taps.") }
                before = nil
            }
            let ocrStarted = Date()
            let reading = try await OCR.read(frame)
            let ocrMs = Self.ms(ocrStarted)
            let decideStarted = Date()
            if let why = Safety.stopReason(reading) { return .blocked(why) }
            let (visible, hidden) = Safety.filter(reading, allowed: s.allowedRisks)
            var context = DecisionContext(subtask: s, reading: visible, jpeg: nil, history: history)
            var decision: Decision?
            var teacher: DecisionContext?  // set when the big brain decided: its answer labels this screen
            if let fast = d.fast {
                do { decision = try await fast.decide(context) } catch { Log.info("fast brain failed: \(error.localizedDescription)") }
            }
            if decision == nil {
                context.jpeg = frame.jpeg()
                decision = try await d.big.decide(context)
                teacher = context
            }
            guard let decision else { continue }
            if let teacher, !decision.action.isDone { learn(teacher, decision.action, step: actions + 1) }
            let thinkMs = Self.ms(decideStarted)
            say("Step \(actions + 1): \(decision.action.name)")
            _ = try? await d.hands.channel.send(.ui(.run, step: actions + 1, total: s.maxActions, text: Self.describe(decision.action, reading)))
            d.progress(actions + 1, s.maxActions, Self.describe(decision.action, reading))
            actions += 1

            switch decision.action {
            case let .done(why):
                let check = try await d.big.verify(s, reading: reading, jpeg: frame.jpeg())
                if let teacher { learn(teacher, decision.action, verified: check.done, step: actions) }
                note("\(decision.source): done (\(why)); check: \(check.done ? "passed" : "failed") \(check.reason)", ms: thinkMs)
                if check.done { return .done(check.reason) }
                history.append("claimed done but the check failed: \(check.reason)")
                continue
            case let .blocked(why):
                note("\(decision.source): blocked: \(why)", ms: thinkMs)
                return .blocked(why)
            case .wait:
                note("\(decision.source): wait", ms: thinkMs)
                history.append("wait")
                try await Task.sleep(for: .seconds(1))
                lastAction = Date()
                continue
            case let .tap(element, point):
                let label = element.flatMap(reading.element)?.text
                // A coordinate tap must not land on a hidden risky button.
                if hidden.contains(where: { id in reading.element(id).map { $0.box.insetBy(dx: -0.01, dy: -0.01).contains(point) } ?? false }) {
                    note("refused a tap on a risky button the task did not ask for", ms: thinkMs)
                    return .blocked("The next step would press a risky button (send, delete, buy) the task did not ask for.")
                }
                let signature = "tap \(label ?? String(format: "%.2f,%.2f", point.x, point.y)) on \(frame.id)"
                if signature == lastSignature { return .blocked("The same tap did not work twice; stopping instead of retrying.") }
                if let label, let e = element.flatMap(reading.element), let kind = Safety.risk(of: e) {
                    say("Waiting for your approval")
                    guard await d.approve("\(kind.capitalized): tap \(label)?") else {
                        note("you declined: \(label)", ms: thinkMs)
                        return .blocked("You declined “\(label)”.")
                    }
                }
                // Freshness: the screen may have moved since it was read; re-check the target before tapping.
                var target = point
                if let label, let latest = d.screen.latest, latest.id != frame.id {
                    let now = try await OCR.read(latest)
                    if let same = now.find(label).min(by: { distance($0.center, point) < distance($1.center, point) }),
                       distance(same.center, point) < 0.05 {
                        target = same.center
                    } else {
                        stale += 1
                        note("target “\(label)” moved; looking again", ms: thinkMs)
                        if stale > 3 { return .blocked("The screen keeps changing under the agent.") }
                        continue
                    }
                }
                let acted = Date()
                let actStarted = Date()
                try await act { try await d.hands.tap(target) }
                let actMs = Self.ms(actStarted)
                note("\(decision.source): tap “\(label ?? "icon")” (\(Int(target.x * 1000)),\(Int(target.y * 1000)))", ms: thinkMs, capture: captureMs, ocr: ocrMs, act: actMs, source: decision.source,
                     recorded: RecordedAction(kind: "tap", target: label, point: target))
                history.append("tap \(element.map { "\($0) " } ?? "")'\(label ?? "icon")'")
                lastSignature = signature
                before = frame
                lastAction = acted
            case let .type(text):
                guard s.inputs.contains(text) else {
                    history.append("refused to type text that is not one of the task's inputs")
                    note("refused to type unexpected text", ms: thinkMs)
                    continue
                }
                if Safety.looksSecret(text) { return .blocked("That looks like a PIN, code or card number; Mantiza never types those.") }
                let acted = Date()
                let actStarted = Date()
                try await act { try await d.hands.type(text) }
                let actMs = Self.ms(actStarted)
                note("\(decision.source): type “\(text)”", ms: thinkMs, capture: captureMs, ocr: ocrMs, act: actMs, source: decision.source,
                     recorded: RecordedAction(kind: "type", text: text))
                history.append("typed '\(text)'")
                before = frame
                lastAction = acted
            case let .scroll(down):
                let acted = Date()
                let actStarted = Date()
                try await act { try await d.hands.scroll(down: down) }
                let actMs = Self.ms(actStarted)
                note("\(decision.source): scroll \(down ? "down" : "up")", ms: thinkMs, capture: captureMs, ocr: ocrMs, act: actMs, source: decision.source,
                     recorded: RecordedAction(kind: down ? "scroll_down" : "scroll_up"))
                history.append("scroll \(down ? "down" : "up")")
                before = frame
                lastAction = acted
            case .back:
                let acted = Date()
                let actStarted = Date()
                try await act { try await d.hands.swipe(from: CGPoint(x: 0.01, y: 0.5), to: CGPoint(x: 0.7, y: 0.5)) }
                let actMs = Self.ms(actStarted)
                note("\(decision.source): back", ms: thinkMs, capture: captureMs, ocr: ocrMs, act: actMs, source: decision.source, recorded: RecordedAction(kind: "back"))
                history.append("back")
                before = frame
                lastAction = acted
            case .home:
                let acted = Date()
                let actStarted = Date()
                try await act { try await d.hands.home() }
                let actMs = Self.ms(actStarted)
                note("\(decision.source): home", ms: thinkMs, capture: captureMs, ocr: ocrMs, act: actMs, source: decision.source, recorded: RecordedAction(kind: "home"))
                history.append("home")
                before = frame
                lastAction = acted
            case let .askUser(question):
                note("\(decision.source): asked you: \(question)", ms: thinkMs)
                say("Waiting for your answer")
                guard let answer = await d.askUser(question) else { return .blocked("No answer to “\(question)”.") }
                history.append("asked the user '\(question)', they said '\(answer)'")
                s.inputs.append(answer)
                note("you said: \(answer)", ms: 0)
                lastAction = Date()
            case let .openApp(name):
                let acted = Date()
                note("\(decision.source): open \(name)", ms: thinkMs, capture: captureMs, ocr: ocrMs, source: decision.source,
                     recorded: RecordedAction(kind: "open_app", text: name))
                try await openApp(name)
                history.append("opened \(name)")
                lastAction = acted
            }
        }
        return .blocked("Used all \(s.maxActions) steps without finishing.")
    }

    private func learn(_ c: DecisionContext, _ action: AgentAction, verified: Bool? = nil, step: Int) {
        if let row = TrainingLog.row(c, decision: action, verified: verified, step: step) { training.append(row) }
    }

    /// A stick command that changes the phone. A timeout means it may or may not have happened, so the run
    /// stops instead of retrying (no blind retries).
    private func act(_ work: () async throws -> Void) async throws {
        do { try await work() } catch let e as BoardError where e.kind == .timeout {
            throw AIError("The stick stopped answering mid-action. Check the screen before trying again.")
        }
    }

    /// Open an app: its URL scheme while Mantiza is in front, otherwise its Home Screen icon.
    private func openApp(_ name: String) async throws {
        let d = deps!
        try await act { try await AppLauncher.open(name, hands: d.hands, screen: d.screen, openURL: d.openURL) }
    }
}

extension AgentRunner {
    /// Short words for the Live Activity: "Tapping “General”", "Typing", "Scrolling".
    static func describe(_ a: AgentAction, _ r: ScreenReading) -> String {
        switch a {
        case let .tap(element, _): return "Tapping " + (element.flatMap(r.element).map { "“\($0.text)”" } ?? "an icon")
        case .type: return "Typing"
        case .scroll: return "Scrolling"
        case .back: return "Going back"
        case .home: return "Going home"
        case let .openApp(name): return "Opening \(name)"
        case .askUser: return "Asking you"
        case .wait: return "Waiting for the screen"
        case .done: return "Checking the result"
        case .blocked: return "Stopping"
        }
    }
}

/// One executed action, kept so a successful run can be replayed as a workflow.
struct RecordedAction: Codable, Equatable {
    var kind: String           // tap, type, scroll_down, scroll_up, back, home, open_app
    var target: String?        // text of the tapped element (nil: an icon)
    var text: String?          // typed text, or the app name
    var point: CGPoint?        // where the tap landed (fallback for icons)
}

@MainActor enum AppLauncher {
    static let maxPages = 15

    /// Open an app: URL scheme when Mantiza is in front (instant), else find its icon label on the Home Screen
    /// pages. Spotlight is not used: iOS leaves it out of screen sharing, so its results cannot be read.
    static func open(_ name: String, hands: Hands, screen: ScreenSource, openURL: (URL) async -> Bool) async throws {
        if let url = AppLinks.url(for: name), await openURL(url) {
            Log.event("launcher.url", ["app": name])
            try await Task.sleep(for: .seconds(1))
            return
        }
        try await hands.home()
        try await Task.sleep(for: .milliseconds(500))
        try await hands.home()  // a second press goes to the first Home Screen page
        var last: Set<String>?
        for page in 0..<maxPages {
            let frame = try await screen.settled(after: Date().addingTimeInterval(-0.1), quiet: 0.4, most: 2)
            let reading = try await OCR.read(frame)
            if let icon = iconHit(name, in: reading) {
                Log.event("launcher.hit", ["app": name, "page": page, "text": icon.text])
                try await hands.tap(icon.center)
                try await Task.sleep(for: .seconds(1))
                return
            }
            // Past the last page when the app names stop changing (pixels keep changing: clock widgets tick).
            let names = pageNames(reading)
            if let last, names == last { break }
            last = names
            try await hands.swipe(from: CGPoint(x: 0.85, y: 0.5), to: CGPoint(x: 0.15, y: 0.5), steps: 20)
            try await Task.sleep(for: .milliseconds(400))
        }
        Log.event("launcher.miss", ["app": name])
        throw AIError("Could not find the \(name) app on the Home Screen.")
    }

    nonisolated static func pageNames(_ reading: ScreenReading) -> Set<String> {
        Set(reading.elements.map { String($0.text.filter(\.isLetter)) }.filter { $0.count >= 3 })
    }

    /// An app icon's label: exact (case-insensitive) match, or a truncated label ("Google Ma...") that starts
    /// the name. Labels sit below their icons, so the tap goes a little above the text.
    nonisolated static func iconHit(_ name: String, in reading: ScreenReading) -> ScreenElement? {
        let q = name.lowercased()
        let match = reading.elements.first { $0.text.lowercased() == q } ?? reading.elements.first { e in
            let t = e.text.lowercased().replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "…", with: "")
                .trimmingCharacters(in: .whitespaces)
            return t.count >= 4 && q.hasPrefix(t)
        }
        guard var hit = match else { return nil }
        hit.box = hit.box.offsetBy(dx: 0, dy: -0.035)  // the icon, not its label
        return hit
    }

    /// The Spotlight result for an app: top-most exact match, else top-most containing match, above the search field.
    nonisolated static func spotlightHit(_ name: String, in reading: ScreenReading) -> ScreenElement? {
        let above = reading.elements.filter { $0.center.y < 0.85 }.sorted { $0.center.y < $1.center.y }
        let q = name.lowercased()
        return above.first { $0.text.lowercased() == q } ?? above.first { $0.text.lowercased().contains(q) }
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

/// URL schemes of built-in apps (opened directly when Mantiza is in front).
enum AppLinks {
    static let schemes: [String: String] = [
        "messages": "sms:", "maps": "maps:", "mail": "message:", "notes": "mobilenotes:", "calendar": "calshow:",
        "photos": "photos-redirect:", "music": "music:", "app store": "itms-apps:", "settings": "App-prefs:",
        "shortcuts": "shortcuts:", "whatsapp": "whatsapp:", "youtube": "youtube:",
        // Third-party apps: opening fails (and the Home Screen search takes over) when the app is not installed.
        "uber eats": "ubereats:", "uber": "uber:", "doordash": "doordash:", "instacart": "instacart:", "lyft": "lyft:",
        "spotify": "spotify:", "instagram": "instagram:", "facebook": "fb:", "x": "twitter:", "slack": "slack:",
        "gmail": "googlegmail:", "chrome": "googlechrome:", "google maps": "comgooglemaps:", "linkedin": "linkedin:",
        "snapchat": "snapchat:", "venmo": "venmo:", "discord": "discord:", "reddit": "reddit:", "telegram": "tg:",
        "zoom": "zoomus:",
    ]

    static func url(for app: String) -> URL? {
        schemes[app.lowercased().trimmingCharacters(in: .whitespaces)].flatMap(URL.init(string:))
    }
}
