import SwiftUI
import UIKit

struct Step: Identifiable {
    let id = UUID()
    let text: String
    let image: UIImage?
}

/// Runs one task: plan → open the app → per step: look → decide → act → repeat until done.
///
/// - Eyes: the captured screen and on-phone text recognition (numbered boxes around text).
/// - Fast brain (Luna Decisions): which box to tap, or type / scroll / done, with a confidence.
/// - Big brain (Gemini 3.5 Flash-Lite): plans once; finds icons with no text and unsure steps.
/// - Hands: the device taps and types.
/// - Safety: asks before risky taps; never repeats a tap that didn't change the screen.
@MainActor
final class Agent: ObservableObject {
    weak var link: DeviceLink?
    weak var capture: ScreenCapture?
    weak var pointer: Pointer?
    let approvals = Approvals()

    @Published var running = false
    @Published var status = "Ready"
    @Published var steps: [Step] = []

    private let fast = FastBrain()
    private let big = BigBrain()
    private var stopRequested = false

    /// Confidence the fast brain needs to act alone (the bench: never wrong at ≥ 0.5).
    private let sure = 0.5
    private static let riskyWords = ["send", "pay", "buy", "order", "delete", "remove", "post", "share",
                                     "call", "confirm", "purchase", "transfer", "publish", "submit"]

    func start(_ request: String) {
        guard !running else { return }
        Task { await run(request.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func stop() {
        stopRequested = true
        status = "Stopping…"
        approvals.answer(false)
    }

    private func add(_ text: String, image: UIImage? = nil) {
        steps.append(Step(text: text, image: image))
        link?.note("[task] \(text)")
    }

    private func end(_ text: String) {
        status = text
        add(text)
    }

    private func seconds(since t: Date) -> String { String(format: "%.1f s", Date().timeIntervalSince(t)) }

    // MARK: - The task

    private func run(_ request: String) async {
        guard let link, let capture, let pointer else { return }
        running = true
        stopRequested = false
        steps = []
        defer { running = false }
        let taskStart = Date()

        guard link.ready else { end("❌ Device not connected (Device tab)"); return }
        guard await link.confirmDevice() else { end("❌ The device doesn't answer. Device tab → Connect again"); return }
        guard pointer.calibrated else { end("❌ Calibrate the pointer first (Device tab)"); return }

        // 1. Plan
        status = "Planning…"
        var t = Date()
        let task: Subtask
        do { task = try await big.plan(request) } catch { end("❌ Couldn't plan: \(error.localizedDescription)"); return }
        add("Plan (\(seconds(since: t))): \(task.goal)" + (task.app.map { " · app: \($0)" } ?? "")
            + (task.text.map { " · text: \"\($0)\"" } ?? ""))

        // 2. Eyes on
        if !capture.running {
            status = "Starting screen sharing…"
            t = Date()
            guard await pointer.startSharing() else { end("❌ Screen sharing didn't start"); return }
            add("Screen sharing on (\(seconds(since: t)))")
        }

        // 3. Start from the Home Screen (never inside Mantiza itself), then open the app:
        //    Control Centre with a swipe down from the top-right corner, like a finger; any other
        //    app with Search (no AI needed, nothing for the user to set up).
        status = "Going to the Home Screen…"
        await link.run("h")
        try? await Task.sleep(for: .milliseconds(700))
        if let app = task.app, app.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix("controlcent") {
            status = "Opening Control Centre…"
            // x 94% (right of the notch / Dynamic Island), from the very top down to 45%
            await link.run("drag 30800 0 30800 14750")
            try? await Task.sleep(for: .milliseconds(900))
            add("Opened Control Centre (swipe down from the top-right)")
        } else if let app = task.app {
            status = "Opening \(app)…"
            t = Date()
            await link.run("k cmd+space")
            try? await Task.sleep(for: .milliseconds(700))
            await link.run("t \(ascii(app))")
            try? await Task.sleep(for: .milliseconds(600))
            await link.run("k enter")
            try? await Task.sleep(for: .milliseconds(800))
            add("Opened \(app) (\(seconds(since: t)))")
        }

        // 4. Look → decide → act
        var typed = false
        var history: [String] = []
        var lastPoint: CGPoint?
        var lastLabel = ""
        var lastScreen = ""  // the text on screen before the last tap
        let maxSteps = min(max(task.max_steps ?? 10, 4), 20)

        for n in 1...maxSteps {
            if stopRequested { end("⏹ Stopped"); return }
            status = "Step \(n): looking…"
            await capture.waitForSettle()

            // Exact check straight from iOS, where it can tell (flashlight, Low Power Mode, Dark Mode)
            if let name = task.state, let want = task.state_value, let now = PhoneState.read(name), now == want {
                let what = name.replacingOccurrences(of: "_", with: " ") + (want ? " is on" : " is off")
                end(history.isEmpty ? "✅ Already done: \(what) (checked with iOS)"
                                    : "✅ Done in \(seconds(since: taskStart)): \(what) (checked with iOS)")
                return
            }

            guard let frame = capture.latestImage() else { end("❌ No screen image"); return }
            t = Date()
            let items = await ScreenReader.read(frame)
            guard let marked = Marks.numbered(frame, items: items), let plain = Marks.plain(frame) else {
                end("❌ Couldn't prepare the screenshot"); return
            }
            let readTime = seconds(since: t)
            let screenText = items.map(\.text).joined(separator: "|")
            let unchanged = !lastScreen.isEmpty && screenText == lastScreen

            // Fast brain
            status = "Step \(n): deciding…"
            t = Date()
            var actions: [(value: String, description: String)] = [
                ("tap", "tap one of the numbered pink boxes (tapping that text itself does what is needed)"),
                ("icon", "tap something with no number: a switch (toggle), a send arrow, back arrow, plus or a picture. To turn a setting on or off, choose this: the switch must be tapped, not its label"),
            ]
            if let text = task.text, !typed {
                actions.append(("type", "type the text \"\(text)\" (only if a text field is selected, the keyboard is showing and the text is not there yet)"))
            }
            actions.append(("scroll", "scroll down to find what is needed"))
            actions.append(("done", "the goal is already reached on this screen"))
            var questions = [
                FastBrain.Question(name: "action", instructions: "What should be done next to reach the goal?", options: actions),
                FastBrain.Question(name: "reached", instructions: "Look at the screen: is the goal already reached? Goal: \(task.goal)",
                                   options: [("yes", "yes, the screen shows the goal is reached"), ("no", "no, not yet")]),
            ]
            if !items.isEmpty {
                questions.append(FastBrain.Question(
                    name: "target", instructions: "If a numbered box should be tapped, which one?",
                    options: items.map { ("\($0.number)", "box \($0.number): \"\($0.text.prefix(60))\"") }))
            }
            let context = "iPhone screen with numbered pink boxes around the text. Goal: \(task.goal)\n"
                + "Steps done so far: \(history.isEmpty ? "none" : history.joined(separator: "; "))"
            var answers: [String: Choice] = [:]
            do { answers = try await fast.ask(context: context, image: marked, questions: questions) } catch {
                // Not fatal: the big brain takes this step.
                add("Step \(n): fast brain didn't answer (\(error.localizedDescription.prefix(80))); asking the big brain")
            }
            let action = answers["action"] ?? Choice(value: "icon", confidence: 0)
            let target = answers["target"]
            let decideTime = seconds(since: t)
            let shot = UIImage(data: marked)

            if let reached = answers["reached"], reached.value == "yes", reached.confidence >= 0.7, !history.isEmpty {
                add("Step \(n): goal reached (\(String(format: "%.0f%%", reached.confidence * 100)) sure)", image: shot)
                end("✅ Done in " + seconds(since: taskStart))
                return
            }

            // Act
            var point: CGPoint?  // in frame pixels
            var label = ""
            switch action.value {
            case "done" where action.confidence >= 0.6:
                let check = task.success_text.flatMap { s in items.contains { $0.text.localizedCaseInsensitiveContains(s) } ? "✓ \"\(s)\" on screen" : nil }
                add("Step \(n): done (\(String(format: "%.0f%%", action.confidence * 100)) sure\(check.map { ", " + $0 } ?? ""))", image: shot)
                end("✅ Done in " + seconds(since: taskStart))
                return
            case "type" where action.confidence >= sure:
                guard let text = task.text else { break }
                await type(text)
                typed = true
                history.append("typed the text")
                add("Step \(n): typed \"\(text)\" · read \(readTime), decide \(decideTime)", image: shot)
                continue
            case "scroll" where action.confidence >= sure:
                await link.run("w -4")
                history.append("scrolled down")
                add("Step \(n): scrolled down · decide \(decideTime)", image: shot)
                continue
            case "tap" where action.confidence >= sure:
                if let target, target.confidence >= sure, let item = items.first(where: { "\($0.number)" == target.value }) {
                    if unchanged && item.text == lastLabel {
                        // Same choice as last time, and the last tap changed nothing: let the big brain look.
                        history.append("tapping \"\(item.text)\" changed nothing")
                    } else {
                        point = item.center
                        label = item.text
                    }
                }
            default:
                break
            }

            if point == nil {  // icon, or the fast brain is unsure: ask the big brain
                status = "Step \(n): looking closer…"
                t = Date()
                do {
                    let p = try await big.locate(image: plain, goal: task.goal, history: history)
                    point = CGPoint(x: p.x * Double(frame.width), y: p.y * Double(frame.height))
                    label = p.what
                    add("Step \(n): big brain → \"\(p.what)\" (\(seconds(since: t))); fast brain said \(action.value) \(String(format: "%.0f%%", action.confidence * 100))")
                } catch {
                    end("❌ Big brain failed: \(error.localizedDescription)"); return
                }
            }
            guard let tapAt = point else { end("❌ Nothing to tap"); return }

            // Safety: ask before anything risky
            if task.needs_approval == true, isRisky(label) {
                status = "Waiting for your OK…"
                add("Step \(n): asking before tapping \"\(label)\"", image: shot)
                guard await approvals.ask("Tap \"\(label)\"? (\(task.goal))") else { end("⏹ Not approved: nothing tapped"); return }
            }

            // Never tap the same thing twice in a row: a switch would just turn back. If the last tap
            // changed the screen, it most likely worked.
            if !unchanged, !lastLabel.isEmpty, label.lowercased() == lastLabel.lowercased() {
                add("Step \(n): \"\(label)\" was just tapped; not tapping it again", image: shot)
                end("✅ Probably done in \(seconds(since: taskStart)) (not checked: iOS doesn't report this setting)")
                return
            }

            // Don't keep tapping the same spot if nothing happens
            let screenPoint = toScreen(tapAt, frame: frame)
            if unchanged, let last = lastPoint, hypot(last.x - screenPoint.x, last.y - screenPoint.y) < 12 {
                end("❌ Stuck: tapping \"\(label)\" doesn't change the screen"); return
            }
            status = "Step \(n): tapping \"\(label)\""
            t = Date()
            guard await pointer.tap(screenPoint) else { end("❌ The device didn't tap"); return }
            add("Step \(n): tapped \"\(label)\" · read \(readTime), decide \(decideTime), tap \(seconds(since: t))", image: shot)
            history.append("tapped \"\(label)\"")
            lastPoint = screenPoint
            lastLabel = label
            lastScreen = screenText
        }
        end("❌ Gave up after \(maxSteps) steps")
    }

    // MARK: - Helpers

    private func isRisky(_ label: String) -> Bool {
        let l = label.lowercased()
        return Self.riskyWords.contains { l.contains($0) } || l.isEmpty
    }

    /// Frame pixels → screen points.
    private func toScreen(_ p: CGPoint, frame: CGImage) -> CGPoint {
        let s = UIScreen.main.bounds.size
        return CGPoint(x: p.x * s.width / CGFloat(frame.width), y: p.y * s.height / CGFloat(frame.height))
    }

    /// The device types US-keyboard characters only (Hindi comes later, by paste).
    private func ascii(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"").filter { $0.isASCII }
    }

    private func type(_ text: String) async {
        var rest = Substring(ascii(text))
        while !rest.isEmpty {
            let chunk = rest.prefix(100)
            await link?.run("t \(chunk)", timeout: 30)
            rest = rest.dropFirst(chunk.count)
        }
    }
}
