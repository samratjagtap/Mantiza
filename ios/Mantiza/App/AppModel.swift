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
            Task { try? await self.channel.send(.prompt(seconds: 60, text: q)) }
        }
        approvals.onResolve = { [weak self] _, source in
            guard let self else { return }
            self.live.answered()
            if source != "stick" { Task { try? await self.channel.send(.unprompt(source == "phone" ? "Answered on phone" : "No answer")) } }
        }
        RunControl.stop = { [weak self] in self?.requestStop() }
        link.onLinkUp = { [weak self] in Task { await self?.suggestNext() } }
        RunControl.answer = { [weak self] yes in self?.approvals.resolve(yes, source: "phone") }
        link.onAudio = { [weak self] packet in
            guard let self else { return }
            talk.audio.key = link.audioKey
            talk.audio.receive(packet)
        }
        talk.onRequest = { [weak self] text in self?.requestFromStick(text) }
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
        case .a:
            // Run the suggestion. Screen sharing can only start with Mantiza in front.
            guard let w = suggestion else { break }
            if UIApplication.shared.applicationState == .active { Task { await run(w) } } else {
                Notifier.tell("Open Mantiza to run “\(w.name)”.")
            }
        case .b, .talkStart, .talkEnd, .talkShort:
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
            try? await channel.send(.ui(.info, text: "Ready.|Hold A to talk."))
            Log.event("session.start")
        } catch {
            Log.event("session.failed", ["error": error.localizedDescription])
        }
    }

    func stopSession() async {
        await screen.stop()
        try? await channel.send(.ui(.info, text: "Session ended.|Open Mantiza to start again."))
        Log.event("session.stop")
    }

    /// A spoken request from the stick: run it if the phone can be operated, else say why on the stick.
    func requestFromStick(_ text: String) {
        let active = UIApplication.shared.applicationState == .active
        let problem: String? =
            runner.running ? "Still working on the last task.|B = stop it" :
            !UIApplication.shared.isProtectedDataAvailable ? "Unlock your iPhone,|then hold A again." :
            !screen.live && !active ? "Open Mantiza and tap|Start session." : nil
        if let problem {
            Log.event("talk.refused", ["why": problem])
            Task { try? await channel.send(.ui(.error, text: problem)) }
            if !screen.live && !active { Notifier.tell("Tap to open Mantiza and start a session, then talk to the stick.") }
            return
        }
        Log.event("talk.request", ["text": text])
        Task { await run(text) }
    }

    func clearStop() { stopRequested = false }
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
            progress: { [weak self] step, total, action in self?.live.progress(step: step, total: total, action: action) },
            findContacts: { await FastPath.findContacts($0) },
            askUser: { [weak self] question in
                await self?.talk.ask(question)
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
        live.start(goal: workflow?.name ?? request)
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
        let record = RunRecord(request: request, plan: runner.subtask, steps: runner.steps, outcome: outcome.summary,
                               success: success, bigBrain: deps.big.name, workflowID: workflow?.id)
        runs.save(record)
        TrainingLog.save(runner.training, run: record.id, success: success)
        lastRecord = record
        if success, let workflow { workflows.used(workflow.id) }
        try? await hands.toggleKeyboard()  // iOS hides the on-screen keyboard while the stick is connected
        await suggestNext()
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
        var snap = WidgetSnapshot()
        snap.tabs[.now] = workflows.suggestions(limit: 6).map(item)
        snap.tabs[.pinned] = workflows.workflows.filter(\.pinned).map(item)
        snap.tabs[.recent] = workflows.workflows.sorted { ($0.uses.last ?? $0.created) > ($1.uses.last ?? $1.created) }
            .prefix(6).map(item)
        snap.save()
    }

    /// mantiza://run/<workflow id> (widget) and mantiza://run?text=<request>.
    func open(_ url: URL) {
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
