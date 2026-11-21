import CoreGraphics
import Foundation

struct ScreenError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static let notSharing = ScreenError(message: "Screen sharing has stopped. Open Mantiza to share the screen again.")
}

/// Where frames come from: ScreenCaptureKit on the phone, still images in tests and the Simulator.
@MainActor protocol ScreenSource: AnyObject {
    var live: Bool { get }
    var latest: Frame? { get }
    /// When `latest` was last known to still show the screen: its capture, or a later "nothing changed"
    /// signal from the system (ScreenCaptureKit sends no new image while the screen is still).
    var confirmedAt: Date? { get }
    func start() async throws
    func stop() async
}

extension ScreenSource {
    /// A tap's effect can take this long to reach the screen; a "still" signal earlier proves nothing.
    static var changeDelay: Double { 0.15 }

    /// Is `latest` known to be current within `seconds`?
    func confirmed(within seconds: Double) -> Bool { Date().timeIntervalSince(confirmedAt ?? .distantPast) <= seconds }

    /// The first frame captured after `date`; or the latest one once the system confirms the screen has not
    /// changed since a little after `date`; or, failing both, the latest one after `timeout`.
    func frame(after date: Date, timeout: Double = 1) async throws -> Frame {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            guard live, let f = latest else { throw ScreenError.notSharing }
            let stillAfter = (confirmedAt ?? .distantPast) > date.addingTimeInterval(Self.changeDelay)
            if f.capturedAt > date || stillAfter || Date() >= deadline { return f }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Wait until the screen stops changing after an action: a new frame (up to 1 s), then no visible change
    /// for `quiet` seconds, at most `most` seconds in all. Returns the settled frame.
    func settled(after action: Date, quiet: Double = 0.25, most: Double = 2) async throws -> Frame {
        let started = Date()
        var current = try await frame(after: action)
        var changedAt = Date()
        while Date().timeIntervalSince(started) < most {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(60))
            guard live, let next = latest else { throw ScreenError.notSharing }
            if next.id != current.id {
                let before = current
                let moved = await Task.detached(priority: .userInitiated) { ScreenDiff.changed(before.image, next.image) }.value
                current = next
                if moved { changedAt = Date() }
            }
            if Date().timeIntervalSince(changedAt) >= quiet { break }
        }
        return current
    }
}

/// Still frames pushed by tests (and the Simulator's demo mode).
@MainActor final class StillScreen: ScreenSource {
    private(set) var latest: Frame?
    var live = true
    /// A still image is always current.
    var confirmedAt: Date? { latest == nil ? nil : Date() }
    private var nextID = 1

    func start() async throws { live = true }
    func stop() async { live = false }

    func show(_ image: CGImage) {
        latest = Frame(image: image, id: nextID, capturedAt: Date())
        nextID += 1
    }
}

/// Did the screen content change? Coarse 32x64 grayscale pass for big changes, then a half-resolution pass
/// for small ones (a checkmark, a typed letter). The status bar and the pointer's parking spot at the left
/// edge (where it fades out after a tap) are ignored.
enum ScreenDiff {
    static func gray(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0..<(w * h)).map { i in
            UInt8((Int(rgba[i * 4]) * 299 + Int(rgba[i * 4 + 1]) * 587 + Int(rgba[i * 4 + 2]) * 114 + 500) / 1000)
        }
    }

    static func changed(_ a: CGImage, _ b: CGImage, threshold: Double = 1.0) -> Bool {
        if a.width != b.width || a.height != b.height { return true }
        let top = Int(OCR.statusBar * 64)
        let sa = gray(a, 32, 64), sb = gray(b, 32, 64)
        let coarse = zip(sa, sb).enumerated().filter { $0.offset / 32 >= top }.reduce(0) { $0 + abs(Int($1.element.0) - Int($1.element.1)) }
        if Double(coarse) / Double(sa.count) > threshold { return true }
        let w = max(1, a.width / 2), h = max(1, a.height / 2)
        let fa = gray(a, w, h), fb = gray(b, w, h)
        let first = Int(OCR.statusBar * Double(h)) * w
        var hits = 0
        let parkX = Int(0.05 * Double(w)), parkY = Int(0.42 * Double(h))...Int(0.58 * Double(h))
        for i in first..<(w * h) where abs(Int(fa[i]) - Int(fb[i])) > 25 {
            if i % w < parkX && parkY.contains(i / w) { continue }
            hits += 1
            if hits >= 6 { return true }
        }
        return false
    }
}
