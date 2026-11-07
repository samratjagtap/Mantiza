import SwiftUI
import UIKit

struct Step: Identifiable {
    let id = UUID()
    let text: String
    let image: UIImage?
}

/// Runs one task like an assistant: the big brain plans it as steps; each step is done straight
/// through iOS when iOS allows it (keys, links, alarms, calendar, contacts, brightness...), and with
/// the AI screen loop only when it doesn't (plan → open the app → look → decide → act → repeat).
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
    @Published var status = "Ready" {
        didSet { showOnDevice(status) }
    }
    @Published var steps: [Step] = []

    private let fast = FastBrain()
    private let big = BigBrain()
    private var stopRequested = false
    private var taskStart = Date()

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
        guard let link, let pointer else { return }
        running = true
        stopRequested = false
        steps = []
        link.send("task on")
        defer {
            running = false
            link.send("task off")
        }
        taskStart = Date()

        guard link.ready else { end("❌ Device not connected (Device tab)"); return }
        guard await link.confirmDevice() else { end("❌ The device doesn't answer. Device tab → Connect again"); return }
        guard pointer.calibrated else { end("❌ Calibrate the pointer first (Device tab)"); return }

        // 1. Plan: which steps iOS can do directly, which need the screen
        status = "Planning…"
        let t = Date()
        let plan: Plan
        do { plan = try await big.plan(request) } catch { end("❌ Couldn't plan: \(error.localizedDescription)"); return }
        add("Plan (\(seconds(since: t))): " + (plan.steps.isEmpty ? "nothing to do" : plan.steps.map(\.summary).joined(separator: " → ")))

        if plan.steps.isEmpty || plan.steps.allSatisfy({ $0.action == "answer" }) {
            let answer = plan.steps.compactMap(\.text).first ?? plan.reply ?? "I'm not sure how to help with that."
            end("💬 " + answer)
            return
        }

        // 2. Do the steps in order
        for (i, step) in plan.steps.enumerated() {
            if stopRequested { end("⏹ Stopped"); return }
            if plan.steps.count > 1 { add("— Step \(i + 1) of \(plan.steps.count): \(step.summary)") }
            guard await perform(step) else {
                if !status.hasPrefix("❌") && !status.hasPrefix("⏹") { end("❌ Couldn't do: \(step.summary)") }
                return
            }
        }
        end("✅ Done in " + seconds(since: taskStart) + (plan.reply.map { " · " + $0 } ?? ""))
    }

    /// One plan step. Direct routes first; the screen loop when iOS has no direct way, or as the
    /// fallback when a direct route doesn't work.
    private func perform(_ step: PlanStep) async -> Bool {
        guard let link else { return false }
        switch step.action {
        case "answer":
            add("💬 " + (step.text ?? ""))
            return true

        case "screen":
            return await runScreen(step.subtask)

        case "open_app":
            guard let app = step.app else { end("❌ Which app?"); return false }
            await open(app: app)
            return true

        case "key":
            guard let key = step.key else { end("❌ Which key?"); return false }
            status = "Pressing \(key)…"
            let reply = await link.run("key \(key)" + ((step.count ?? 1) > 1 ? " \(step.count!)" : ""))
            guard reply.hasPrefix("ok") else {
                end("❌ The device can't press \(key) (\(reply)). Update the device firmware"); return false
            }
            add("Pressed \(key)" + ((step.count ?? 1) > 1 ? " × \(step.count!)" : "") + " (device key)")
            return true

        case "brightness":
            guard let v = step.value else { end("❌ How bright?"); return false }
            Direct.brightness(v)
            add(String(format: "Brightness set to %.0f%% (directly)", min(max(v, 0), 1) * 100))
            return true

        case "flashlight":
            let on = step.on ?? true
            status = "Turning the flashlight \(on ? "on" : "off")…"
            if await bringMantizaForward(), await Direct.flashlight(on) {
                add("Flashlight \(on ? "on" : "off") (directly, checked with iOS)")
                return true
            }
            add("Direct flashlight didn't work; using Control Centre")
            return await runScreen(Subtask(app: "Control Center", goal: "The flashlight is \(on ? "on" : "off")",
                                           text: nil, success_text: nil, needs_approval: false, max_steps: 6,
                                           state: "flashlight", state_value: on))

        case "alarm":
            guard let time = step.time else { end("❌ What time?"); return false }
            status = "Setting an alarm…"
            do {
                let what = try await Direct.alarm(time: time, days: step.days ?? [], label: step.text)
                add("⏰ Alarm set: \(what) (directly)")
                return true
            } catch { end("❌ Alarm: \(error.localizedDescription)"); return false }

        case "timer":
            guard let s = step.seconds else { end("❌ How long?"); return false }
            status = "Setting a timer…"
            do {
                let what = try await Direct.timer(seconds: s, label: step.text)
                add("⏱ Timer set: \(what) (directly)")
                return true
            } catch { end("❌ Timer: \(error.localizedDescription)"); return false }

        case "event":
            status = "Adding to the calendar…"
            do {
                let what = try await Direct.event(title: step.text ?? "Event", start: step.start, end: step.end)
                add("📅 Added \(what) (directly)")
                return true
            } catch { end("❌ Calendar: \(error.localizedDescription)"); return false }

        case "reminder":
            status = "Adding a reminder…"
            do {
                let what = try await Direct.reminder(title: step.text ?? "Reminder", due: step.start)
                add("📝 Reminder \(what) (directly)")
                return true
            } catch { end("❌ Reminders: \(error.localizedDescription)"); return false }

        case "call", "whatsapp", "sms", "email":
            return await message(step)

        case "directions":
            guard let place = step.destination else { end("❌ Directions to where?"); return false }
            status = "Getting directions…"
            let google = (step.maps ?? "").lowercased().contains("google")
            guard await bringMantizaForward() else { return false }
            if let url = Direct.directionsURL(to: place, mode: step.mode, google: google), await Direct.open(url) {
                add("🗺 Directions to \(place) in \(google ? "Google Maps" : "Apple Maps") (link)")
                return true
            }
            if google, let url = Direct.directionsURL(to: place, mode: step.mode, google: false), await Direct.open(url) {
                add("🗺 Google Maps didn't open; directions in Apple Maps (link)")
                return true
            }
            end("❌ Maps didn't open"); return false

        default:
            // Unknown kind: let the screen loop try it if the planner gave it a goal.
            if step.goal != nil { return await runScreen(step.subtask) }
            end("❌ Don't know how to do \"\(step.action)\""); return false
        }
    }

    /// Calls and messages: the number from Contacts, then a link that opens the right screen with
    /// the text already in place; the screen loop only taps Send (or Call). Without a number, the
    /// whole thing goes to the screen loop.
    private func message(_ step: PlanStep) async -> Bool {
        let kind = step.action
        let who = step.contact ?? step.phone ?? step.email ?? ""
        status = "Looking up \(who)…"
        var person: Direct.Person?
        if let phone = step.phone, !phone.isEmpty {
            person = Direct.Person(name: phone, phone: Direct.international(phone), email: nil)
        } else if let email = step.email, !email.isEmpty, kind == "email" {
            person = Direct.Person(name: email, phone: nil, email: email)
        } else if let name = step.contact, !name.isEmpty {
            person = await Direct.lookUp(name)
            if let person { add("Found \(person.name) in Contacts") } else { add("\(name) isn't in Contacts (or no permission)") }
        }

        let appName = ["call": "Phone", "whatsapp": "WhatsApp", "sms": "Messages", "email": "Mail"][kind] ?? kind
        let what = step.text.map { "\"\($0)\"" } ?? ""
        let url: URL? = switch kind {
        case "call": person?.phone.flatMap { Direct.callURL(phone: $0) }
        case "whatsapp": person?.phone.flatMap { Direct.whatsAppURL(phone: $0, text: step.text) }
        case "sms": person?.phone.flatMap { Direct.smsURL(phone: $0, text: step.text) }
        default: person?.email.flatMap { Direct.mailURL(to: $0, subject: step.subject, body: step.text) }
        }

        guard let url else {
            // No number or address: do it all on screen.
            add("No direct link; doing it on screen")
            let goal = kind == "call" ? "A phone call to \(who) has started"
                : "The message \(what) has been sent to \(who) in \(appName) (it shows as a sent message)"
            return await runScreen(Subtask(app: appName, goal: goal, text: step.text, success_text: nil,
                                           needs_approval: false, max_steps: 12, state: nil, state_value: nil))
        }

        // Eyes first (sharing starts from Mantiza), then the link.
        guard let capture else { return false }
        if !capture.running { guard await startEyes() else { return false } }
        guard await bringMantizaForward() else { return false }
        status = kind == "call" ? "Calling \(person?.name ?? who)…" : "Opening \(appName) with the message…"
        guard await Direct.open(url, appOnly: kind == "whatsapp") else {
            if kind == "whatsapp" { end("❌ WhatsApp didn't open (is it installed?)") } else { end("❌ \(appName) didn't open") }
            return false
        }
        add("Opened \(appName) for \(person?.name ?? who) (link)" + (kind == "call" ? "" : " with \(what) filled in"))
        try? await Task.sleep(for: .milliseconds(1200))

        if kind == "call" {
            // iOS may ask "Call …?" first: tap Call. If it dials straight away, nothing to tap.
            if await tapText(["Call"], within: 3) { add("Tapped Call") }
            return true
        }
        return await runScreen(Subtask(app: nil,
                                       goal: "The message \(what) is sent to \(person?.name ?? who) in \(appName): it shows as a sent message in the chat, not in the text box",
                                       text: nil, success_text: nil, needs_approval: false, max_steps: 5,
                                       state: nil, state_value: nil),
                               openApp: false, typedAlready: true)
    }

    // MARK: - Getting around

    /// Home Screen: the device's Home key (Apple's consumer Home usage); ⌘H on older firmware.
    private func goHome() async {
        guard let link else { return }
        let reply = await link.run("key home")
        if !reply.hasPrefix("ok") { await link.run("h") }
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// Opens an app by name through Search, from the Home Screen.
    private func open(app: String) async {
        guard let link else { return }
        status = "Opening \(app)…"
        let t = Date()
        await goHome()
        await link.run("k cmd+space")
        try? await Task.sleep(for: .milliseconds(700))
        await link.run("t \(ascii(app))")
        try? await Task.sleep(for: .milliseconds(600))
        await link.run("k enter")
        try? await Task.sleep(for: .milliseconds(800))
        add("Opened \(app) (\(seconds(since: t)))")
    }

    /// Screen sharing (Mantiza's eyes). The picker shows inside Mantiza, so it comes forward first.
    private func startEyes() async -> Bool {
        guard let pointer else { return false }
        status = "Starting screen sharing…"
        let t = Date()
        guard await bringMantizaForward() else { return false }
        guard await pointer.startSharing() else { end("❌ Screen sharing didn't start"); return false }
        add("Screen sharing on (\(seconds(since: t)))")
        return true
    }

    /// Links and the torch only work while Mantiza is on screen. If it isn't, the device opens it.
    private func bringMantizaForward() async -> Bool {
        if UIApplication.shared.applicationState == .active { return true }
        guard let link else { return false }
        await link.run("k cmd+space")
        try? await Task.sleep(for: .milliseconds(700))
        await link.run("t Mantiza")
        try? await Task.sleep(for: .milliseconds(600))
        await link.run("k enter")
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(150))
            if UIApplication.shared.applicationState == .active { return true }
        }
        end("❌ Couldn't bring Mantiza to the front"); return false
    }

    /// Taps a button by its exact text (e.g. "Call") if it shows up within a few seconds.
    private func tapText(_ words: [String], within limit: Double) async -> Bool {
        guard let capture, let pointer else { return false }
        let until = Date().addingTimeInterval(limit)
        while Date() < until {
            await capture.waitForSettle(quiet: 0.3, maxWait: 1.5)
            if let frame = capture.latestImage() {
                let items = await ScreenReader.read(frame)
                if let item = items.first(where: { i in words.contains { $0.caseInsensitiveCompare(i.text.trimmingCharacters(in: .whitespaces)) == .orderedSame } }) {
                    return await pointer.tap(toScreen(item.center, frame: frame))
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    /// The AI loop: looks at the screen, decides with the fast brain (big brain when unsure or for
    /// icons), taps, and repeats until the goal is reached. Returns whether it got there; on failure
    /// it has already said why.
    private func runScreen(_ task: Subtask, openApp: Bool = true, typedAlready: Bool = false) async -> Bool {
        guard let link, let capture, let pointer else { return false }
        if !capture.running {
            guard await startEyes() else { return false }
        }
        var t = Date()
        add("Screen step: \(task.goal)" + (task.app.map { " · app: \($0)" } ?? "") + (task.text.map { " · text: \"\($0)\"" } ?? ""))

        // 3. Start from the Home Screen (never inside Mantiza itself), then open the app:
        //    Control Centre with a swipe down from the top-right corner, like a finger; any other
        //    app with Search (no AI needed, nothing for the user to set up).
        if openApp, let app = task.app, app.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix("controlcent") {
            status = "Going to the Home Screen…"
            await goHome()
            status = "Opening Control Centre…"
            // x 94% (right of the notch / Dynamic Island), from the very top down to 45%
            await link.run("drag 30800 0 30800 14750")
            try? await Task.sleep(for: .milliseconds(900))
            add("Opened Control Centre (swipe down from the top-right)")
        } else if openApp, let app = task.app {
            await open(app: app)
        }

        // 4. Look → decide → act
        var typed = typedAlready
        var typeTries = 0
        var history: [String] = []
        var lastPoint: CGPoint?
        var lastLabel = ""
        var lastScreen = ""  // the text on screen before the last tap
        let maxSteps = min(max(task.max_steps ?? 10, 4), 20)

        for n in 1...maxSteps {
            if stopRequested { end("⏹ Stopped"); return false }
            status = "Step \(n): looking…"
            await capture.waitForSettle()

            // Exact check straight from iOS, where it can tell (flashlight, Low Power Mode, Dark Mode)
            if let name = task.state, let want = task.state_value, let now = PhoneState.read(name), now == want {
                let what = name.replacingOccurrences(of: "_", with: " ") + (want ? " is on" : " is off")
                add(history.isEmpty ? "✅ Already so: \(what) (checked with iOS)"
                                    : "✅ \(what) (checked with iOS)")
                return true
            }

            guard let frame = capture.latestImage() else { end("❌ No screen image"); return false }
            t = Date()
            let items = await ScreenReader.read(frame)
            guard let marked = Marks.numbered(frame, items: items), let plain = Marks.plain(frame) else {
                end("❌ Couldn't prepare the screenshot"); return false
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
                actions.append(("type", "tap the text field (e.g. the message box) and type \"\(text)\" into it. Choose this as soon as the right text field is on screen (e.g. the right chat is open). There is no on-screen keyboard: a Bluetooth keyboard is connected, so iOS hides it"))
            }
            actions.append(("scroll", "scroll down to find what is needed"))
            actions.append(("done", "the goal is already reached on this screen"))
            var questions = [
                FastBrain.Question(name: "action", instructions: "What should be done next to reach the goal?", options: actions),
                FastBrain.Question(name: "reached", instructions: "Look at the screen: is the goal already reached? Goal: \(task.goal)"
                                   + " (a message counts as sent only when it shows as a sent bubble in the chat, not while it is still in the text field)",
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

            let textPending = task.text != nil && !typed  // never "done" before the text is typed
            if let reached = answers["reached"], reached.value == "yes", reached.confidence >= 0.7, !history.isEmpty, !textPending {
                add("Step \(n): goal reached (\(String(format: "%.0f%%", reached.confidence * 100)) sure)", image: shot)
                return true
            }

            // Act
            var point: CGPoint?  // in frame pixels
            var label = ""
            switch action.value {
            case "done" where action.confidence >= 0.6 && !textPending:
                let check = task.success_text.flatMap { s in items.contains { $0.text.localizedCaseInsensitiveContains(s) } ? "✓ \"\(s)\" on screen" : nil }
                add("Step \(n): done (\(String(format: "%.0f%%", action.confidence * 100)) sure\(check.map { ", " + $0 } ?? ""))", image: shot)
                return true
            case "type" where action.confidence >= 0.4:
                guard let text = task.text else { break }
                // 1. Tap into the text field (the big brain finds it: it often has no text, or only a
                //    grey placeholder like "Message"). 2. Type. 3. Check the text shows on screen.
                status = "Step \(n): finding the text box…"
                t = Date()
                let field: TapPoint
                do {
                    field = try await big.locate(image: plain,
                                                 goal: "Tap inside the text field where \"\(text)\" must be typed (for a chat: the message box at the bottom)",
                                                 history: [])
                } catch { end("❌ Big brain failed: \(error.localizedDescription)"); return false }
                let fieldPoint = toScreen(CGPoint(x: field.x * Double(frame.width), y: field.y * Double(frame.height)), frame: frame)
                guard await pointer.tap(fieldPoint) else { end("❌ The device didn't tap"); return false }
                try? await Task.sleep(for: .milliseconds(500))
                status = "Step \(n): typing \"\(text)\""
                await type(text)
                await capture.waitForSettle()
                let shown = await textShows(text)
                typeTries += 1
                if shown {
                    typed = true
                    history.append("tapped the text field and typed \"\(text)\" (it shows in the field; not sent yet)")
                    add("Step \(n): typed \"\(text)\" into \"\(field.what)\" (\(seconds(since: t)))", image: shot)
                } else if typeTries >= 2 {
                    end("❌ Typed twice, but the text doesn't show on screen"); return false
                } else {
                    history.append("tapped \"\(field.what)\" and typed, but the text did not appear")
                    add("Step \(n): typed into \"\(field.what)\", but the text doesn't show; trying again", image: shot)
                }
                lastLabel = ""
                lastScreen = ""
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
                    end("❌ Big brain failed: \(error.localizedDescription)"); return false
                }
            }
            guard let tapAt = point else { end("❌ Nothing to tap"); return false }

            // Safety: ask before anything risky
            if task.needs_approval == true, isRisky(label) {
                status = "Waiting for your OK…"
                add("Step \(n): asking before tapping \"\(label)\"", image: shot)
                guard await approvals.ask("Tap \"\(label)\"? (\(task.goal))") else { end("⏹ Not approved: nothing tapped"); return false }
            }

            // Never tap the same thing twice in a row: a switch would just turn back. If the last tap
            // changed the screen, it most likely worked.
            if !unchanged, !lastLabel.isEmpty, label.lowercased() == lastLabel.lowercased() {
                add("Step \(n): \"\(label)\" was just tapped; not tapping it again", image: shot)
                add("Probably done (not checked: iOS doesn't report this setting)")
                return true
            }

            // Don't keep tapping the same spot if nothing happens
            let screenPoint = toScreen(tapAt, frame: frame)
            if unchanged, let last = lastPoint, hypot(last.x - screenPoint.x, last.y - screenPoint.y) < 12 {
                end("❌ Stuck: tapping \"\(label)\" doesn't change the screen"); return false
            }
            status = "Step \(n): tapping \"\(label)\""
            t = Date()
            guard await pointer.tap(screenPoint) else { end("❌ The device didn't tap"); return false }
            add("Step \(n): tapped \"\(label)\" · read \(readTime), decide \(decideTime), tap \(seconds(since: t))", image: shot)
            history.append("tapped \"\(label)\"")
            lastPoint = screenPoint
            lastLabel = label
            lastScreen = screenText
        }
        end("❌ Gave up after \(maxSteps) steps")
        return false
    }

    // MARK: - Helpers

    /// The device's screen shows what Mantiza is doing (plain letters only: its font has no emoji).
    private func showOnDevice(_ text: String) {
        guard let link, link.ready else { return }
        var t = text.replacingOccurrences(of: "✅", with: "Done:").replacingOccurrences(of: "❌", with: "Failed:")
            .replacingOccurrences(of: "⏹", with: "Stopped:").replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        t = String(t.filter { $0.isASCII && !$0.isNewline }.prefix(120)).trimmingCharacters(in: .whitespaces)
        link.send("status " + t)
    }

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

    /// Whether the typed text is now readable on screen (the first few words are enough).
    private func textShows(_ text: String) async -> Bool {
        guard let frame = capture?.latestImage() else { return false }
        if text.contains(where: { !$0.isASCII }) { return true }  // pasted; on-phone reading can't check every script
        let want = String(text.prefix(14)).lowercased().filter { $0.isLetter || $0.isNumber }
        guard !want.isEmpty else { return true }
        let onScreen = await ScreenReader.read(frame).map(\.text).joined(separator: " ")
            .lowercased().filter { $0.isLetter || $0.isNumber }
        return onScreen.contains(want)
    }

    private func type(_ text: String) async {
        if text.contains(where: { !$0.isASCII }) {
            // Hindi, emoji, accents: put it on the clipboard and paste with ⌘V, then put the old
            // clipboard back.
            let old = UIPasteboard.general.string
            UIPasteboard.general.string = text
            await link?.run("k cmd+v")
            try? await Task.sleep(for: .milliseconds(600))
            if let old { UIPasteboard.general.string = old }
            return
        }
        var rest = Substring(text)
        while !rest.isEmpty {
            let chunk = rest.prefix(100)
            await link?.run("t \(chunk)", timeout: 30)
            rest = rest.dropFirst(chunk.count)
        }
    }
}
