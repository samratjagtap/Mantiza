import CoreGraphics
import Foundation

/// Gestures on the phone's screen, in screen fractions (0...1, top-left origin), through the stick.
/// The firmware wakes the hidden pointer by itself before acting; taps end with `park` so the pointer
/// never covers what the next screenshot needs to read.
@MainActor final class Hands {
    let channel: CommandChannel
    var calibration: Calibration

    /// Longest text per `type` command (well under the 512-byte command buffer and one BLE write).
    nonisolated static let chunk = 120

    init(channel: CommandChannel, calibration: Calibration = .identity) {
        self.channel = channel
        self.calibration = calibration
    }

    func tap(_ p: CGPoint) async throws {
        let (x, y) = calibration.units(p)
        try await channel.send(.tap(x, y))
        try await channel.send(.park)
    }

    func longPress(_ p: CGPoint, ms: Int = 1000) async throws {
        let (x, y) = calibration.units(p)
        try await channel.send(.longPress(x, y, ms: ms))
        try await channel.send(.park)
    }

    func swipe(from a: CGPoint, to b: CGPoint, steps: Int = 30) async throws {
        let (x1, y1) = calibration.units(a), (x2, y2) = calibration.units(b)
        try await channel.send(.stroke(x1, y1, x2, y2, steps: steps))
        try await channel.send(.park)
    }

    /// Scroll the content by about a quarter screen (a slow finger swipe in the middle: fast ones fling the
    /// list past what we were looking for).
    func scroll(down: Bool) async throws {
        let top = CGPoint(x: 0.5, y: 0.4), bottom = CGPoint(x: 0.5, y: 0.65)
        try await swipe(from: down ? bottom : top, to: down ? top : bottom, steps: 80)
    }

    /// Types US-ASCII text. Throws before typing anything if a character cannot be typed.
    func type(_ text: String) async throws {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII && ($0.value >= 0x20 || $0.value == 0x09) }) else {
            throw BoardError(kind: .refused, message: "The stick can only type plain English letters, digits and symbols.")
        }
        for part in Self.chunks(text) {
            if part == " " { try await channel.send(.key("space")) } else { try await channel.send(.type(part)) }
        }
    }

    func key(_ combo: String) async throws { try await channel.send(.key(combo)) }
    func home() async throws { try await channel.send(.home) }

    /// Home, checked: when the screen did not change, try Cmd+H, then a swipe up from the bottom edge (some apps
    /// and states ignore the Home key). `screen` nil: just the key.
    func home(checking screen: ScreenSource?) async throws {
        let before = screen?.latest
        try await home()
        guard let screen, let before else { return }
        let fallbacks: [() async throws -> Void] = [
            { try await self.channel.send(.key("cmd+h")) },
            { try await self.swipe(from: CGPoint(x: 0.5, y: 0.995), to: CGPoint(x: 0.5, y: 0.55), steps: 12) },
        ]
        for fallback in fallbacks {
            try await Task.sleep(for: .milliseconds(700))
            if let now = screen.latest, now.id != before.id, ScreenDiff.changed(before.image, now.image) { return }
            Log.info("home: the screen did not change; trying the next way home")
            try await fallback()
        }
    }
    /// Show (or hide) the on-screen keyboard, which iOS hides while a hardware keyboard is connected.
    func toggleKeyboard() async throws { try await channel.send(.keyboardToggle) }

    /// Split text for `type`. The board trims each command line, so no part may end with a space: trailing
    /// spaces move to the next part, and spaces at the very end are sent one by one as `key space` (part " ").
    nonisolated static func chunks(_ text: String, size: Int = chunk) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            var part = rest.prefix(size)
            while part.last == " " { part = part.dropLast() }
            if part.isEmpty {  // a run of spaces: send one as a key and carry on
                parts.append(" ")
                rest = rest.dropFirst()
                continue
            }
            parts.append(String(part))
            rest = rest.dropFirst(part.count)
        }
        return parts
    }
}
