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

    struct Step: Identifiable, Equatable {
        let id: Int
        let text: String
        let ms: Int
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
    }

    private(set) var subtask: Subtask?
    private(set) var steps: [Step] = []
    private(set) var status = ""
    private(set) var outcome: Outcome?
    var running: Bool { outcome == nil && !status.isEmpty }

    @ObservationIgnored private var deps: Deps!
    @ObservationIgnored private var history: [String] = []

    /// Plan the request with the big brain, then run it.
    func run(_ request: String, deps: Deps, prepare: () async throws -> Void = {}) async -> Outcome {
        self.deps = deps
        steps = []; outcome = nil; history = []
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
        steps = []; outcome = nil; history = []; subtask = plan
        do { return finish(try await execute(plan)) } catch is CancellationError { return finish(.stopped) } catch {
            return finish(.failed(error.localizedDescription))
        }
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

    private func note(_ text: String, ms: Int) {
        steps.append(Step(id: steps.count + 1, text: text, ms: ms))
        Log.event("run.step", ["n": steps.count, "text": text, "ms": ms])
    }

    private func execute(_ s: Subtask) async throws -> Outcome {
        let d = deps!
        if let app = s.app {
            say("Opening \(app)")
            try await openApp(app)
        }
        var lastAction = Date()
        var before: Frame?           // the frame the last screen-changing action was taken on
        var lastSignature = ""       // action + target on that frame, to refuse a blind repeat
        var noChange = 0, stale = 0, actions = 0
        while actions < s.maxActions {
            if d.shouldStop() { return .stopped }
            try Task.checkCancellation()
            let started = Date()
            let frame = try await d.screen.settled(after: lastAction)
            if let previous = before {
                let changed = ScreenDiff.changed(previous.image, frame.image)
                noChange = changed ? 0 : noChange + 1
                history[history.count - 1] += changed ? " -> screen changed" : " -> no change"
                if noChange >= 3 { return .blocked("The screen stopped responding to taps.") }
                before = nil
            }
            let reading = try await OCR.read(frame)
            if let why = Safety.stopReason(reading) { return .blocked(why) }
            let (visible, hidden) = Safety.filter(reading, allowed: s.allowedRisks)
            var context = DecisionContext(subtask: s, reading: visible, jpeg: nil, history: history)
            var decision: Decision?
            if let fast = d.fast {
                do { decision = try await fast.decide(context) } catch { Log.info("fast brain failed: \(error.localizedDescription)") }
            }
            if decision == nil {
                context.jpeg = frame.jpeg()
                decision = try await d.big.decide(context)
            }
            guard let decision else { continue }
            let thinkMs = Int(Date().timeIntervalSince(started) * 1000)
            say("Step \(actions + 1): \(decision.action.name)")
            _ = try? await d.hands.channel.send(.ui(.run, step: actions + 1, total: s.maxActions, text: decision.action.name))
            actions += 1

            switch decision.action {
            case let .done(why):
                let check = try await d.big.verify(s, reading: reading, jpeg: frame.jpeg())
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
                try await act { try await d.hands.tap(target) }
                note("\(decision.source): tap “\(label ?? "icon")” (\(Int(target.x * 1000)),\(Int(target.y * 1000)))", ms: thinkMs)
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
                try await act { try await d.hands.type(text) }
                note("\(decision.source): type “\(text)”", ms: thinkMs)
                history.append("typed '\(text)'")
                before = frame
                lastAction = acted
            case let .scroll(down):
                let acted = Date()
                try await act { try await d.hands.scroll(down: down) }
                note("\(decision.source): scroll \(down ? "down" : "up")", ms: thinkMs)
                history.append("scroll \(down ? "down" : "up")")
                before = frame
                lastAction = acted
            case .back:
                let acted = Date()
                try await act { try await d.hands.swipe(from: CGPoint(x: 0.01, y: 0.5), to: CGPoint(x: 0.7, y: 0.5)) }
                note("\(decision.source): back", ms: thinkMs)
                history.append("back")
                before = frame
                lastAction = acted
            case .home:
                let acted = Date()
                try await act { try await d.hands.home() }
                note("\(decision.source): home", ms: thinkMs)
                history.append("home")
                before = frame
                lastAction = acted
            case let .openApp(name):
                let acted = Date()
                try await openApp(name)
                note("\(decision.source): open \(name)", ms: thinkMs)
                history.append("opened \(name)")
                lastAction = acted
            }
        }
        return .blocked("Used all \(s.maxActions) steps without finishing.")
    }

    /// A stick command that changes the phone. A timeout means it may or may not have happened, so the run
    /// stops instead of retrying (no blind retries).
    private func act(_ work: () async throws -> Void) async throws {
        do { try await work() } catch let e as BoardError where e.kind == .timeout {
            throw AIError("The stick stopped answering mid-action. Check the screen before trying again.")
        }
    }

    /// Open an app: its URL scheme while Mantiza is in front, otherwise Spotlight via the keyboard.
    private func openApp(_ name: String) async throws {
        let d = deps!
        if let url = AppLinks.url(for: name), await d.openURL(url) {
            try await Task.sleep(for: .seconds(1))
            return
        }
        try await act {
            try await d.hands.home()
            try await Task.sleep(for: .milliseconds(600))
            try await d.hands.key("cmd+space")
            try await Task.sleep(for: .milliseconds(600))
            try await d.hands.type(name)
            try await Task.sleep(for: .milliseconds(500))
            try await d.hands.key("enter")
        }
        try await Task.sleep(for: .seconds(1))
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

/// URL schemes of built-in apps (opened directly when Mantiza is in front).
enum AppLinks {
    static let schemes: [String: String] = [
        "messages": "sms:", "maps": "maps:", "mail": "message:", "notes": "mobilenotes:", "calendar": "calshow:",
        "photos": "photos-redirect:", "music": "music:", "app store": "itms-apps:", "settings": "App-prefs:",
        "shortcuts": "shortcuts:", "whatsapp": "whatsapp:", "youtube": "youtube:",
    ]

    static func url(for app: String) -> URL? {
        schemes[app.lowercased().trimmingCharacters(in: .whitespaces)].flatMap(URL.init(string:))
    }
}
