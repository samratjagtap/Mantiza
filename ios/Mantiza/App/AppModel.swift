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
    var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    /// The last device event (button / shake), for the UI.
    private(set) var lastEvent: BoardEvent?
    /// Set when the stick asks to stop (B held or shaken); the agent loop checks it between actions.
    private(set) var stopRequested = false

    init() {
        #if targetEnvironment(simulator)
        let useMock = true
        #else
        let useMock = UserDefaults.standard.bool(forKey: "mockBoard")
        #endif
        mock = useMock ? MockBoard() : nil
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
        if event == .stop { stopRequested = true }
    }

    func clearStop() { stopRequested = false }

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
