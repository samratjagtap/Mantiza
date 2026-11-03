import Foundation
import UIKit

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Self-healing runs: a lost stick, pointer or screen sharing pauses the run (AgentRunner.waitForRecovery); this
/// side reports the link, shows each stage (log, Live Activity, widget, stick) and notifies when the user must act.
extension AppModel {
    /// The link as the agent sees it.
    func recoveryLink() -> Recovery.Link {
        let seen = max(screen.latest?.capturedAt ?? .distantPast, screen.confirmedAt ?? .distantPast)
        return Recovery.Link(stick: boardConnected, pointer: inputReady, screen: screen.live,
                             frameAt: seen.timeIntervalSince1970)
    }

    func recover(_ stage: Recovery.Stage?) {
        let was = recovering
        recovering = stage
        guard let stage else {
            if was != nil {
                live.note("Back online. Going on from here…")
                canvas.update(now: true) { $0.phase = .working; $0.question = nil; $0.status = "Back online" }
            }
            return
        }
        if stage.part != .stick, was == nil || was?.part == .stick, let up = boardStatus?.up, up < 60_000 {
            Log.event("run.stick_rebooted", ["seconds_ago": up / 1000, "reset": boardStatus?.rst ?? "?"])
        }
        live.note(stage.line)
        canvas.update(now: true) { $0.phase = .waiting; $0.status = stage.line }
        if stage.part != .stick { Task { _ = try? await channel.send(.ui(.info, text: "Paused:|" + stage.line)) } }
        if stage.ask { Notifier.tell(stage.line) }
    }

    /// Mantiza came to the front while a run waits for screen sharing: ask for it again (the picker needs the app
    /// in front, so this is the one moment it can start).
    func resumeScreenIfWaiting() {
        guard recovering?.part == .screen, !screen.live,
              UIApplication.shared.applicationState == .active else { return }
        Log.event("run.screen_restart")
        Task { try? await screen.start() }
    }
}
