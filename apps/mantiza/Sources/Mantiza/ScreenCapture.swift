import CoreImage
import ScreenCaptureKit
import SwiftUI
import UIKit

/// Receives frames on a background queue and keeps the newest one. iOS sends a frame only when the
/// screen changes, so "no new frame for a moment" means the screen has settled.
final class FrameStore: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var lastFrameAt = Date.distantPast
    private var count = 0

    func reset() {
        lock.lock(); latest = nil; lastFrameAt = .distantPast; count = 0; lock.unlock()
    }

    func read() -> (buffer: CVPixelBuffer?, lastFrameAt: Date, count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (latest, lastFrameAt, count)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let image = sampleBuffer.imageBuffer else { return }
        lock.lock()
        latest = image
        lastFrameAt = Date()
        count += 1
        lock.unlock()
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

    /// Waits until no new frame has arrived for `quiet` seconds (the screen stopped changing),
    /// or `maxWait` seconds have passed.
    func waitForSettle(quiet: Double = 0.45, maxWait: Double = 4) async {
        let start = Date()
        while Date().timeIntervalSince(start) < maxWait {
            if Date().timeIntervalSince(store.read().lastFrameAt) >= quiet { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
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
