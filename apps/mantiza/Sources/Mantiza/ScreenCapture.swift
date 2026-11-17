import CoreImage
import ScreenCaptureKit
import SwiftUI
import UIKit

/// Receives frames on a background queue and keeps the newest one.
///
/// "Settled" means the PICTURE stopped changing, not that frames stopped coming: iOS keeps sending
/// frames for things that don't matter (the clock, the red recording pill, a blinking text cursor),
/// so waiting for "no new frame" nearly always ran to its time limit (about 2.5 s of every AI step
/// in the debug runs of 2026-11-13). Each frame is reduced to a grid of brightness samples and
/// compared with the one before; only a real difference counts as a change.
final class FrameStore: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var lastFrameAt = Date.distantPast
    private var lastChangeAt = Date.distantPast
    private var count = 0
    private var changes = 0
    private var grid: [UInt8] = []

    private static let cols = 32, rows = 70          // one sample about every 13 pt on an iPhone
    private static let skipTop = 0.06                // status bar: clock, battery, recording pill
    private static let tolerance = 14                // brightness steps (of 255) that count as different
    private static let minSamples = 3                // fewer changed samples than this: a cursor blink, noise

    func reset() {
        lock.lock(); latest = nil; lastFrameAt = .distantPast; lastChangeAt = .distantPast
        count = 0; changes = 0; grid = []; lock.unlock()
    }

    func read() -> (buffer: CVPixelBuffer?, lastFrameAt: Date, count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (latest, lastFrameAt, count)
    }

    /// When the picture last really changed, and how many times it has.
    func changed() -> (at: Date, count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (lastChangeAt, changes)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let image = sampleBuffer.imageBuffer else { return }
        let now = Self.samples(of: image)
        lock.lock()
        var differs = grid.count != now.count
        if !differs {
            var n = 0
            for i in 0..<now.count where abs(Int(now[i]) - Int(grid[i])) > Self.tolerance {
                n += 1
                if n >= Self.minSamples { differs = true; break }
            }
        }
        if differs {
            grid = now
            lastChangeAt = Date()
            changes += 1
        }
        latest = image
        lastFrameAt = Date()
        count += 1
        lock.unlock()
    }

    /// A grid of brightness samples below the status bar (green channel of BGRA, or the luma plane).
    private static func samples(of buffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        let w = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let h = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer),
              w > cols, h > rows else { return [] }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let step = planar ? 1 : 4, offset = planar ? 0 : 1
        let top = Int(Double(h) * skipTop)
        var out = [UInt8](repeating: 0, count: cols * rows)
        for r in 0..<rows {
            let y = top + (h - top) * (2 * r + 1) / (2 * rows)
            for c in 0..<cols {
                let x = w * (2 * c + 1) / (2 * cols)
                out[r * cols + c] = bytes[y * rowBytes + x * step + offset]
            }
        }
        return out
    }
}

/// The app's eyes: screen capture with ScreenCaptureKit (iOS 27).
/// Capture is started once (picker) and kept running between tasks (tests T3/T4). Locking the
/// phone stops it; the next task starts it again, with the device pressing the picker's button.
@MainActor
final class ScreenCapture: NSObject, ObservableObject {
    weak var link: DeviceLink?

    @Published var state = "Off"
    @Published var running = false
    @Published private(set) var starts = 0

    private var stream: SCStream?
    private let store = FrameStore()
    private let queue = DispatchQueue(label: "mantiza.capture")
    private let ciContext = CIContext()
    private var observing = false

    private func note(_ text: String) { link?.note("[eyes] \(text)") }

    // MARK: - Start / stop

    /// Shows Apple's picker. The capture starts when "Share Entire Screen" is pressed (by the user
    /// or by the device).
    func showPicker() {
        let picker = SCContentSharingPicker.shared
        if !observing {
            picker.add(self)
            observing = true
        }
        picker.isActive = true
        state = "Waiting for the picker…"
        picker.present()
    }

    func stop() {
        guard let s = stream else { return }
        Task {
            try? await s.stopCapture()
            finish("Off")
        }
    }

    private func start(with filter: SCContentFilter) {
        if let old = stream { Task { try? await old.stopCapture() } }
        let config = SCStreamConfiguration()
        // Half of the screen's pixels: enough to read text, and small enough to send quickly.
        let scale = CGFloat(filter.pointPixelScale)
        let rect = filter.contentRect
        if rect.width > 0, rect.height > 0, scale > 0 {
            config.width = Int(rect.width * scale / 2)
            config.height = Int(rect.height * scale / 2)
        } else {
            config.width = Int(UIScreen.main.bounds.width * UIScreen.main.scale / 2)
            config.height = Int(UIScreen.main.bounds.height * UIScreen.main.scale / 2)
        }
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(store, type: .screen, sampleHandlerQueue: queue)
        } catch {
            note("Couldn't add output: \(describe(error))")
            state = "Failed"
            return
        }
        stream = s
        store.reset()
        state = "Starting…"
        Task {
            do {
                try await s.startCapture()
                starts += 1
                running = true
                state = "On ✅"
                note("Capture on, \(config.width)×\(config.height)")
            } catch {
                note("Start failed: \(describe(error))")
                finish("Start failed")
            }
        }
    }

    private func finish(_ newState: String) {
        running = false
        stream = nil
        state = newState
    }

    // MARK: - Frames

    /// The newest frame, or nil if nothing has arrived yet.
    func latestImage() -> CGImage? {
        guard let buffer = store.read().buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    /// Waits until the picture hasn't changed for `quiet` seconds, or `maxWait` seconds have passed.
    func waitForSettle(quiet: Double = 0.45, maxWait: Double = 4) async {
        let start = Date()
        while Date().timeIntervalSince(start) < maxWait {
            if Date().timeIntervalSince(store.changed().at) >= quiet { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// How many times the picture has changed so far. Read it BEFORE an action, then pass it to
    /// `settle(after:)`.
    var changeCount: Int { store.changed().count }

    /// After an action (a tap, a swipe): waits for the screen to START changing (up to `react`
    /// seconds; a tap takes a moment to show), then for it to settle. Returns false if the screen
    /// never changed, so the action did nothing visible.
    @discardableResult
    func settle(after mark: Int, react: Double = 0.8, quiet: Double = 0.35, maxWait: Double = 2.5) async -> Bool {
        let start = Date()
        while store.changed().count == mark {
            if Date().timeIntervalSince(start) >= react { return false }
            try? await Task.sleep(for: .milliseconds(40))
        }
        await waitForSettle(quiet: quiet, maxWait: max(0.5, maxWait - Date().timeIntervalSince(start)))
        return true
    }

    /// Number of frames so far (changes whenever the screen changes).
    var frameCount: Int { store.read().count }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        let names: [Int: String] = [
            -3801: "user declined", -3802: "failed to start", -3807: "already capturing",
            -3815: "no capture source", -3817: "stopped by the user", -3821: "stopped by the system",
        ]
        return "\(ns.code) \(names[ns.code] ?? ns.localizedDescription)"
    }
}

extension ScreenCapture: @preconcurrency SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        state = "Picker cancelled"
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        note("Picker chose the content (Mantiza \(UIApplication.shared.applicationState == .active ? "in front" : "behind"))")
        start(with: filter)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        note("Picker failed: \(describe(error))")
        state = "Picker failed"
    }
}

extension ScreenCapture: @preconcurrency SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        note("Capture stopped by iOS: \(describe(error))")
        finish("Off (stopped by iOS)")
    }
}
