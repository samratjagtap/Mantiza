import Foundation

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Healing a run after a lost link instead of failing it: which part is missing (the stick's app link, the
/// pointer, screen sharing), when to ask the user, and when to give up. Pure: the agent polls it with the link
/// state and the time.
struct Recovery {
    /// What the app sees of the link right now.
    struct Link: Equatable {
        var stick: Bool      // BLE link up and this app authenticated
        var pointer: Bool    // the phone takes the stick's pointer and keyboard input
        var screen: Bool     // screen sharing on
        var frameAt: Double  // newest frame or "still" signal (seconds since 1970)
    }

    enum Part: Equatable { case stick, pointer, screen }

    struct Stage: Equatable {
        var part: Part
        var ask: Bool  // waited long enough: the user has to do something
    }

    enum Next: Equatable {
        case wait(Stage)
        case live
        case giveUp(String)
    }

    /// How long each part may come back by itself before the user is asked; then the whole limit.
    static let quiet: [Part: Double] = [.stick: 30, .pointer: 20, .screen: 10]
    static let limit = 300.0

    let started: Double
    let limit: Double
    private(set) var stage: Stage?
    private var partSince = 0.0

    init(at t: Double, limit: Double = Self.limit) { started = t; self.limit = limit }

    /// Live once the stick and pointer are back and the screen has shown something newer than the loss.
    mutating func next(_ l: Link, at t: Double) -> Next {
        let part: Part? = !l.stick ? .stick : !l.pointer ? .pointer : !l.screen || l.frameAt <= started ? .screen : nil
        guard let part else { stage = nil; return .live }
        if part != stage?.part { partSince = t }
        stage = Stage(part: part, ask: t - partSince >= Self.quiet[part]!)
        if t - started >= limit { return .giveUp(Self.reason(part)) }
        return .wait(stage!)
    }

    static func reason(_ part: Part) -> String {
        switch part {
        case .stick: return "The stick did not come back in 5 minutes."
        case .pointer: return "The pointer did not come back in 5 minutes."
        case .screen: return "Screen sharing did not come back in 5 minutes."
        }
    }
}

extension Recovery.Stage {
    /// One sentence for the run log, the Live Activity, the widget, the stick and the notification.
    var line: String {
        switch (part, ask) {
        case (.stick, false): return "Lost the stick. Reconnecting…"
        case (.stick, true): return "The stick is still gone. Keep it near the phone and switched on; the task goes on when it is back."
        case (.pointer, false): return "The pointer dropped. Waiting for iOS to reconnect it…"
        case (.pointer, true): return "The pointer is still off. Check Settings > Accessibility > Touch > AssistiveTouch > Devices."
        case (.screen, false): return "Screen sharing paused. Waiting for it…"
        case (.screen, true): return "Screen sharing stopped. Unlock the phone and open Mantiza to continue the task."
        }
    }
}
