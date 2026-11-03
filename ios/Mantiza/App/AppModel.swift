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
        RunControl.answer = { [weak self] yes in self?.approvals.resolve(yes, source: "phone") }
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
        Log.event("board.event", ["name": event.rawValue])
        switch event {
        case .stop:
            stopRequested = true
            approvals.resolve(false, source: "stick")
        case .yes: approvals.resolve(true, source: "stick")
        case .no, .timeout: approvals.resolve(false, source: "stick")
        default: break
        }
    }

    func clearStop() { stopRequested = false }
    func requestStop() { stopRequested = true }

    /// Ask on the stick (A = yes, B = no), the Live Activity and a notification; the first answer counts.
    func approve(_ question: String) async -> Bool {
        await approvals.ask(question)
    }

    /// Plan and run a request end to end.
    func run(_ request: String) async {
        clearStop()
        let deps: AgentRunner.Deps
        do {
            deps = AgentRunner.Deps(
                hands: hands, screen: screen, big: try AISettings.bigBrain(), fast: AISettings.fastBrain(),
                approve: { [weak self] q in await self?.approve(q) ?? false },
                shouldStop: { [weak self] in self?.stopRequested ?? true },
                openURL: { url in
                    guard UIApplication.shared.applicationState == .active else { return false }
                    return await UIApplication.shared.open(url)
                },
                progress: { [weak self] step, total, action in self?.live.progress(step: step, total: total, action: action) },
                findContacts: { await FastPath.findContacts($0) })
        } catch {
            _ = await runner.run(request, deps: AgentRunner.Deps(
                hands: hands, screen: screen, big: MissingBrain(message: error.localizedDescription), fast: nil,
                approve: { _ in false }, shouldStop: { true }, openURL: { _ in false }))
            return
        }
        let screen = self.screen
        live.start(goal: request)
        let outcome = await runner.run(request, deps: deps, prepare: {
            if !screen.live { try await screen.start() }
        })
        live.end(outcome.summary)
        let record = RunRecord(request: request, plan: runner.subtask, steps: runner.steps, outcome: outcome.summary,
                               success: { if case .done = outcome { return true }; return false }(),
                               bigBrain: deps.big.name)
        runs.save(record)
        lastRecord = record
        try? await hands.toggleKeyboard()  // iOS hides the on-screen keyboard while the stick is connected
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
