import Foundation
import Observation
import UIKit

/// App-wide state: the stick (real or mock), gestures, calibration and onboarding progress.
@MainActor @Observable final class AppModel {
    let link = BoardLink()
    /// The pretend stick, in the Simulator or when launched with `-mockBoard YES`.
    let mock: MockBoard?
    let hands: Hands
    let calibrator = Calibrator()
    let runner = AgentRunner()
    let approvals = Approvals()
    let live = LiveRun()
    let runs = RunStore()
    let workflows = WorkflowStore()
    /// Push-to-talk on the stick.
    let talk: StickTalk
    /// The full-screen agent widget.
    let canvas = CanvasPublisher()
    /// Set while a run waits for a lost link to come back (RunRecovery).
    var recovering: Recovery.Stage?
    /// The user paused the running task (A on the stick, or Pause on the Live Activity / Run tab).
    private(set) var paused = false
    /// The running task's id; Live Activity buttons from any other run are ignored.
    private(set) var runID = ""
    /// The workflow shown as "Next" on the stick.
    private(set) var suggestion: Workflow?
    /// The phone's screen (ScreenCaptureKit), or still demo images in the Simulator.
    let screen: ScreenSource
    var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    /// The last device event (button / shake), for the UI.
    private(set) var lastEvent: BoardEvent?
    /// The last saved run (the Run tab offers to save it as a workflow).
    private(set) var lastRecord: RunRecord?
    /// Set when the stick asks to stop (B held or shaken); the agent loop checks it between actions.
    private(set) var stopRequested = false

    init() {
        #if targetEnvironment(simulator)
        let useMock = true
        #else
        let useMock = UserDefaults.standard.bool(forKey: "mockBoard")
        #endif
        mock = useMock ? MockBoard() : nil
        #if targetEnvironment(simulator)
        screen = StillScreen()
        #else
        screen = ScreenCaptureFeed()
        #endif
        let channel = mock?.commands ?? link.commands
        hands = Hands(channel: channel, calibration: CalibrationStore.load(screen: Screen.size) ?? .identity)
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        talk = StickTalk(channel: channel)
        channel.onEvent = { [weak self] event in self?.received(event) }
        channel.onSent = { line, result, ms in
            switch result {
            case let .success(text): Log.event("cmd", ["line": line, "ok": true, "ms": Int(ms), "text": text])
            case let .failure(error): Log.event("cmd", ["line": line, "ok": false, "ms": Int(ms), "error": error.localizedDescription])
            }
        }
        approvals.onAsk = { [weak self] q in
            guard let self else { return }
            self.live.ask(q)
            self.canvas.update(now: true) { $0.phase = .waiting; $0.question = q }
            Task { try? await self.channel.send(.prompt(seconds: 60, text: q)) }
        }
        approvals.onResolve = { [weak self] _, source in
            guard let self else { return }
            self.live.answered()
            self.canvas.update { $0.phase = .working; $0.question = nil }
            if source != "stick" { Task { try? await self.channel.send(.unprompt(source == "phone" ? "Answered on phone" : "No answer")) } }
        }
        RunControl.stop = { [weak self] id in if id == self?.runID { self?.requestStop() } }
        RunControl.pause = { [weak self] id in if id == self?.runID { self?.togglePause() } }
        LiveRun.endStale()
        link.onLinkUp = { [weak self] in Task { await self?.suggestNext() } }
        RunControl.answer = { [weak self] yes in self?.approvals.resolve(yes, source: "phone") }
        link.onAudio = { [weak self] packet in
            guard let self else { return }
            talk.audio.key = link.audioKey
            talk.audio.receive(packet)
        }
        talk.onRequest = { [weak self] text in self?.requestFromStick(text) }
        talk.onGaveUp = { [weak self] in
            guard let self, canvas.canvas.phase == .listening else { return }
            canvas.update(now: true) { $0.phase = .idle }
        }
        if mock == nil { link.start() }
        Log.event("app.start", ["mock": useMock, "onboarded": onboarded])
    }

    var channel: CommandChannel { hands.channel }
    var boardConnected: Bool { mock?.isConnected ?? link.connected }
    var boardStatus: BoardStatus? { mock?.status ?? link.status }
    /// The phone takes the stick's pointer and keyboard input.
    var inputReady: Bool { boardConnected && boardStatus?.inputReady == true }
    var boardName: String { mock != nil ? "Mantiza Hands (mock)" : link.name }
    var calibrated: Bool { hands.calibration.verified }

    func received(_ event: BoardEvent) {
        lastEvent = event
        Log.event("board.event", ["name": event.name])
        switch event {
        case .stop:
            stopRequested = true
            approvals.resolve(false, source: "stick")
        case .yes: approvals.resolve(true, source: "stick")
        case .no, .timeout: approvals.resolve(false, source: "stick")
        case .a where runner.running:
            togglePause()
        case .b where paused:
            requestStop()
        case .a:
            // Run the suggestion. Screen sharing can only start with Mantiza in front.
            guard let w = suggestion else { break }
            if UIApplication.shared.applicationState == .active { Task { await run(w) } } else {
                Notifier.tell("Open Mantiza to run “\(w.name)”.")
            }
        case .talkStart:
            if !runner.running { canvas.update(now: true) { $0.phase = .listening; $0.question = nil } }
            talk.handle(event)
        case .b, .talkEnd, .talkShort:
            talk.handle(event)
        default: break
        }
    }

    /// Screen sharing is on, so requests from the stick can run with the phone on any screen.
    var sessionLive: Bool { screen.live }

    /// Start a session: share the screen once; then the stick does the rest.
    func startSession() async {
        do {
            try await screen.start()
            canvas.update(now: true) { $0.session = true }
            try? await channel.send(.ui(.info, text: "Ready.|Hold A to talk."))
            Log.event("session.start")
        } catch {
            Log.event("session.failed", ["error": error.localizedDescription])
        }
    }

    func stopSession() async {
        await screen.stop()
        canvas.update(now: true) { $0.session = false }
        try? await channel.send(.ui(.info, text: "Session ended.|Open Mantiza to start again."))
        Log.event("session.stop")
    }

    /// A spoken request from the stick: run it if the phone can be operated, else say why on the stick.
    func requestFromStick(_ text: String) {
        let active = UIApplication.shared.applicationState == .active
        if runner.running {  // said during a task: an extra instruction for it
            runner.amend(text)
            Log.event("run.amended", ["text": text])
            Task { try? await channel.send(.ui(.info, text: "Got it:|" + text)) }
            return
        }
        let problem: String? =
            !UIApplication.shared.isProtectedDataAvailable ? "Unlock your iPhone,|then hold A again." :
            !screen.live && !active ? "Open Mantiza and tap|Start session." : nil
        if let problem {
            Log.event("talk.refused", ["why": problem])
            if canvas.canvas.phase == .listening { canvas.update(now: true) { $0.phase = .idle } }
            Task { try? await channel.send(.ui(.error, text: problem)) }
            if !screen.live && !active { Notifier.tell("Tap to open Mantiza and start a session, then talk to the stick.") }
            return
        }
        Log.event("talk.request", ["text": text])
        Task { await run(text) }
    }

    func clearStop() { stopRequested = false; paused = false }

    /// Pause between actions, or go on (the agent looks again first and never replays the last action).
    func togglePause() {
        guard runner.running else { return }
        paused.toggle()
        Log.event(paused ? "run.paused" : "run.resumed")
        live.paused(paused)
        canvas.update(now: true) {
            $0.phase = self.paused ? .waiting : .working
            $0.status = self.paused ? "Paused" : "Going on"
        }
        Task {
            if paused { _ = try? await channel.send(.park) }
            _ = try? await channel.send(paused ? .ui(.info, text: "Paused.|A = go on  B = stop|Hold A to add to the task")
                                               : .ui(.run, text: "Going on"))
        }
    }
    func requestStop() { stopRequested = true }

    /// Ask on the stick (A = yes, B = no), the Live Activity and a notification; the first answer counts.
    func approve(_ question: String) async -> Bool {
        await approvals.ask(question)
    }

    private func makeDeps() throws -> AgentRunner.Deps {
        AgentRunner.Deps(
            hands: hands, screen: screen, big: try AISettings.bigBrain(), fast: AISettings.fastBrain(),
            approve: { [weak self] q in await self?.approve(q) ?? false },
            shouldStop: { [weak self] in self?.stopRequested ?? true },
            openURL: { url in
                guard UIApplication.shared.applicationState == .active else { return false }
                return await UIApplication.shared.open(url)
            },
            progress: { [weak self] step, total, action in
                guard let self else { return }
                live.progress(step: step, total: total, action: action)
                let steps = runner.steps.suffix(6).map { AgentCanvas.Step(id: $0.id, text: $0.text) }
                canvas.update(thumbnail: screen.latest) {
                    $0.phase = .working; $0.question = nil
                    $0.step = step; $0.total = total; $0.status = action; $0.steps = steps
                }
            },
            findContacts: { await FastPath.findContacts($0) },
            link: { [weak self] in self?.recoveryLink() ?? Recovery.Link(stick: false, pointer: false, screen: false, frameAt: 0) },
            onRecover: { [weak self] stage in self?.recover(stage) },
            askHelp: { [weak self] reason in
                await self?.approve("Stuck: \(reason) Fix it by hand, then A = go on, B = stop.") ?? false
            },
            paused: { [weak self] in self?.paused ?? false },
            askUser: { [weak self] question in
                guard let self else { return nil }
                canvas.update(now: true) { $0.phase = .waiting; $0.question = question }
                let answer = await talk.ask(question)
                canvas.update { $0.phase = .working; $0.question = nil }
                return answer
            })
    }

    /// Plan and run a request end to end.
    func run(_ request: String) async {
        await perform(request: request, workflow: nil)
    }

    /// Run a saved workflow (replay, with the AI only where the screen differs).
    func run(_ workflow: Workflow) async {
        await perform(request: workflow.request, workflow: workflow)
    }

    private func perform(request: String, workflow: Workflow?) async {
        guard !runner.running else { return }
        clearStop()
        let deps: AgentRunner.Deps
        do { deps = try makeDeps() } catch {
            _ = await runner.run(request, deps: AgentRunner.Deps(
                hands: hands, screen: screen, big: MissingBrain(message: error.localizedDescription), fast: nil,
                approve: { _ in false }, shouldStop: { true }, openURL: { _ in false }))
            return
        }
        let screen = self.screen
        runID = UUID().uuidString
        live.start(goal: workflow?.name ?? request, runID: runID)
        // The stick takes a silent app during a task as a crash (firmware APP_SILENT_MS) and lets go of everything.
        let heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                _ = try? await self?.channel.send(.ping)
            }
        }
        defer { heartbeat.cancel() }
        canvas.update(now: true) {
            $0.phase = .working; $0.request = workflow?.name ?? request; $0.status = "Planning"
            $0.step = 0; $0.total = 0; $0.steps = []; $0.card = nil; $0.question = nil; $0.session = screen.live
        }
        let outcome: AgentRunner.Outcome
        if let workflow {
            do {
                if !screen.live { try await screen.start() }
                outcome = await runner.replay(workflow, deps: deps)
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        } else {
            outcome = await runner.run(request, deps: deps, prepare: {
                if !screen.live { try await screen.start() }
            })
        }
        live.end(outcome.summary)
        let success = { if case .done = outcome { return true }; return false }()
        await publishResult(outcome, success: success, brain: deps.big)
        let record = RunRecord(request: request, plan: runner.subtask, steps: runner.steps, outcome: outcome.summary,
                               success: success, bigBrain: deps.big.name, workflowID: workflow?.id)
        runs.save(record)
        TrainingLog.save(runner.training, run: record.id, success: success)
        lastRecord = record
        if success, let workflow { workflows.used(workflow.id) }
        try? await hands.toggleKeyboard()  // iOS hides the on-screen keyboard while the stick is connected
        await suggestNext()
    }

    /// The widget's result card (written by the AI from the final screen when the task succeeded), also on the stick.
    private func publishResult(_ outcome: AgentRunner.Outcome, success: Bool, brain: BigBrain) async {
        var card = AgentCanvas.Card(headline: success ? "Done" : "Stopped", detail: outcome.summary,
                                    symbol: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        if success, let s = runner.subtask, let frame = screen.latest, let reading = try? await OCR.read(frame),
           let written = try? await brain.summarize(s, outcome: outcome.summary, reading: reading, jpeg: frame.jpeg()) {
            card = written
            _ = try? await channel.send(.ui(.done, text: card.headline + "|" + card.detail))
        }
        let steps = runner.steps.suffix(6).map { AgentCanvas.Step(id: $0.id, text: $0.text) }
        canvas.update(now: true, thumbnail: screen.latest) {
            $0.phase = success ? .done : .failed; $0.status = outcome.summary; $0.card = card
            $0.steps = steps; $0.question = nil; $0.session = screen.live
        }
    }

    /// Save the last successful run as a workflow.
    @discardableResult
    func saveLastAsWorkflow() -> Workflow? {
        guard let r = lastRecord, let w = Workflow(from: r) else { return nil }
        workflows.add(w)
        Log.event("workflow.saved", ["name": w.name, "steps": w.steps.count])
        Task { await suggestNext() }
        return w
    }

    /// Show the best workflow for this time of day on the stick ("Next: ... A") and refresh the widget.
    func suggestNext() async {
        publishWidget()
        let next = workflows.suggestions().first
        suggestion = next
        _ = try? await channel.send(.next(next.map { String($0.name.prefix(24)) } ?? ""))
    }

    /// Write the widget's tabs into the App Group.
    func publishWidget() {
        func item(_ w: Workflow) -> WidgetSnapshot.Item { .init(id: w.id.uuidString, name: w.name, app: w.subtask.app) }
        let suggestions = workflows.suggestions(limit: 3).map(item)
        if suggestions != canvas.canvas.suggestions { canvas.update { $0.suggestions = suggestions } }
        var snap = WidgetSnapshot()
        snap.tabs[.now] = workflows.suggestions(limit: 6).map(item)
        snap.tabs[.pinned] = workflows.workflows.filter(\.pinned).map(item)
        snap.tabs[.recent] = workflows.workflows.sorted { ($0.uses.last ?? $0.created) > ($1.uses.last ?? $1.created) }
            .prefix(6).map(item)
        snap.save()
    }

    /// mantiza://run/<workflow id> (widget) and mantiza://run?text=<request>.
    func open(_ url: URL) {
        if url.scheme == "mantiza", url.host == "session" {  // from the agent widget
            if !screen.live { Task { await startSession() } }
            return
        }
        guard url.scheme == "mantiza", url.host == "run" else { return }
        Log.event("deeplink", ["url": url.absoluteString])
        if let id = UUID(uuidString: url.lastPathComponent), let w = workflows.workflow(id) {
            Task { await run(w) }
        } else if let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value {
            Task { await run(text) }
        }
    }

    /// Delete runs, workflows, approvals, calibration and keys.
    func deleteAllData() {
        runs.deleteAll()
        workflows.deleteAll()
        TrainingLog.deleteAll()
        approvals.clearHistory()
        resetCalibration()
        KeyStore.Provider.allCases.forEach { KeyStore.set($0, nil) }
        suggestion = nil
        lastRecord = nil
        Log.event("privacy.deleted")
    }

    /// Load the calibration saved for this screen size (call once a window exists).
    func reloadCalibration() {
        hands.calibration = CalibrationStore.load(screen: Screen.size) ?? .identity
    }

    func resetCalibration() {
        CalibrationStore.clear()
        hands.calibration = .identity
    }
}

@MainActor enum Screen {
    static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Points.
    static var size: CGSize { scene?.screen.bounds.size ?? CGSize(width: 390, height: 844) }
}
