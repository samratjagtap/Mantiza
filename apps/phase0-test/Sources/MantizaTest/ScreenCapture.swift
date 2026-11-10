import CoreImage
import ScreenCaptureKit
import SwiftUI
import UIKit

/// Receives frames on a background queue. Only counts them and keeps the newest one.
final class FrameCounter: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Stats {
        var frames = 0
        var backgroundFrames = 0
        var lastFrame: Date?
        var longestGap: TimeInterval = 0
        var latest: CVPixelBuffer?
    }

    private let lock = NSLock()
    private var stats = Stats()
    private var inBackground = false

    func setBackground(_ value: Bool) {
        lock.lock(); inBackground = value; lock.unlock()
    }

    func reset() {
        lock.lock(); stats = Stats(); lock.unlock()
    }

    func read() -> Stats {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let image = sampleBuffer.imageBuffer else { return }
        let now = Date()
        lock.lock()
        stats.frames += 1
        if inBackground { stats.backgroundFrames += 1 }
        if let last = stats.lastFrame { stats.longestGap = max(stats.longestGap, now.timeIntervalSince(last)) }
        stats.lastFrame = now
        stats.latest = image
        lock.unlock()
    }
}

struct Thumb: Identifiable {
    let id = UUID()
    let time: Date
    let background: Bool
    let image: UIImage
}

/// T3 and T4: screen capture with ScreenCaptureKit (iOS 27).
@MainActor
final class ScreenCapture: NSObject, ObservableObject {
    weak var link: DeviceLink?

    @Published var state = "Stopped"
    @Published var running = false
    @Published var hasSavedChoice = false
    @Published var frames = 0
    @Published var backgroundFrames = 0
    @Published var lastFrameAgo = "–"
    @Published var longestGap = "–"
    @Published var runningFor = "–"
    @Published var pickersShown = 0
    @Published var starts = 0
    @Published var thumbs: [Thumb] = []

    private var stream: SCStream?
    private var savedFilter: SCContentFilter?
    private let counter = FrameCounter()
    private let queue = DispatchQueue(label: "mantiza.capture")
    private let ciContext = CIContext()
    private var startedAt: Date?
    private var lastThumbAt = Date.distantPast
    private var ticker: Task<Void, Never>?
    private var observing = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.counter.setBackground(true) }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.counter.setBackground(false) }
        }
    }

    private func note(_ text: String) { link?.note("[capture] \(text)") }

    // MARK: - Start / stop

    /// T3 / T4: ask the user with the system picker.
    func startWithPicker() {
        let picker = SCContentSharingPicker.shared
        if !observing {
            picker.add(self)
            observing = true
        }
        note("Screen recording available: \(picker.isAvailable)")
        picker.isActive = true
        pickersShown += 1
        state = "Waiting for the picker…"
        note("Picker shown (#\(pickersShown))")
        picker.present()
    }

    /// T4: start again with the earlier choice, without showing the picker.
    func restartWithoutPicker() {
        guard let filter = savedFilter else {
            note("No saved choice yet: use Start first")
            return
        }
        note("Restarting with the saved choice (no picker)")
        start(with: filter)
    }

    func stop() {
        guard let s = stream else { return }
        Task {
            do {
                try await s.stopCapture()
                note("Stopped by the app")
            } catch {
                note("Stop error: \(describe(error))")
            }
            finish(state: "Stopped")
        }
    }

    func clearThumbs() { thumbs.removeAll() }

    private func start(with filter: SCContentFilter) {
        if running { stop() }
        let config = SCStreamConfiguration()
        // Half of the screen's pixel size: enough to read text, half the memory.
        let scale = CGFloat(filter.pointPixelScale)
        let rect = filter.contentRect
        if rect.width > 0, rect.height > 0, scale > 0 {
            config.width = Int(rect.width * scale / 2)
            config.height = Int(rect.height * scale / 2)
        } else {  // fallback: half of an iPhone 14 Plus screen
            config.width = 642
            config.height = 1389
        }

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(counter, type: .screen, sampleHandlerQueue: queue)
        } catch {
            note("Add output failed: \(describe(error))")
            state = "Failed"
            return
        }
        stream = s
        counter.reset()
        state = "Starting…"
        Task {
            do {
                try await s.startCapture()
                starts += 1
                startedAt = Date()
                running = true
                state = "Capturing ✅"
                note("Capture started (#\(starts)), \(config.width)×\(config.height)")
                startTicker()
            } catch {
                note("Start failed: \(describe(error))")
                finish(state: "Start failed")
            }
        }
    }

    private func finish(state newState: String) {
        running = false
        stream = nil
        ticker?.cancel()
        ticker = nil
        state = newState
        refresh()
    }

    // MARK: - Stats

    private func startTicker() {
        ticker?.cancel()
        ticker = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        let s = counter.read()
        frames = s.frames
        backgroundFrames = s.backgroundFrames
        longestGap = s.frames > 1 ? String(format: "%.1f s", s.longestGap) : "–"
        if let last = s.lastFrame {
            lastFrameAgo = String(format: "%.0f s ago", Date().timeIntervalSince(last))
        }
        if let started = startedAt, running {
            let sec = Int(Date().timeIntervalSince(started))
            runningFor = String(format: "%d:%02d", sec / 60, sec % 60)
        }
        // A thumbnail every 20 s shows what was actually captured.
        if running, let latest = s.latest, Date().timeIntervalSince(lastThumbAt) >= 20 {
            lastThumbAt = Date()
            let bg = UIApplication.shared.applicationState == .background
            if let image = thumbnail(latest) {
                thumbs.insert(Thumb(time: Date(), background: bg, image: image), at: 0)
                if thumbs.count > 30 { thumbs.removeLast() }
            }
            note("\(s.frames) frames so far, \(s.backgroundFrames) in background\(bg ? " (app in background)" : "")")
        }
    }

    private func thumbnail(_ buffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: 0.3, y: 0.3))
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        let names: [Int: String] = [
            -3801: "user declined", -3802: "failed to start", -3803: "missing entitlements",
            -3807: "already capturing", -3811: "internal error", -3815: "no capture source",
            -3817: "stopped by the user", -3821: "stopped by the system",
            -3823: "not supported", -3824: "missing background mode",
        ]
        return "\(ns.code) \(names[ns.code] ?? ns.localizedDescription)"
    }
}

extension ScreenCapture: @preconcurrency SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        note("Picker cancelled")
        state = "Cancelled"
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        note("Picker: user chose \(filter.style == .display ? "the screen" : "a window/app") (\(Int(filter.contentRect.width))×\(Int(filter.contentRect.height)) pt)")
        savedFilter = filter
        hasSavedChoice = true
        start(with: filter)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        note("Picker failed: \(describe(error))")
        state = "Picker failed"
    }
}

extension ScreenCapture: @preconcurrency SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        note("Capture STOPPED by iOS: \(describe(error))")
        finish(state: "Stopped: \(describe(error))")
    }
}
