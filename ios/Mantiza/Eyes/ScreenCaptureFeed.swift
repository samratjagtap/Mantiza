import CoreImage
import CoreMedia
import Foundation
import Observation
import UIKit
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo fork, MIT); see THIRD_PARTY_NOTICES.md.

/// Full-screen capture with the user's consent (system picker, iOS 27 ScreenCaptureKit). Keeps only the latest
/// frame, at most 4 per second, scaled to at most 960 px wide. One stream lasts a whole task.
@MainActor @Observable final class ScreenCaptureFeed: NSObject, ScreenSource {
    private(set) var latest: Frame?
    private(set) var choosing = false
    private(set) var capturing = false
    private(set) var note = ""
    @ObservationIgnored var onStopped: ((String) -> Void)?
    @ObservationIgnored private var frameID = 0
    #if canImport(ScreenCaptureKit)
    @ObservationIgnored private lazy var picker = SCContentSharingPicker.shared
    @ObservationIgnored private var callbacks: CaptureCallbacks!
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: CaptureOutput?
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var selection: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var registered = false
    #endif

    override init() {
        super.init()
        #if canImport(ScreenCaptureKit)
        callbacks = CaptureCallbacks(owner: self)
        #endif
    }

    var live: Bool { capturing && latest != nil }

    /// Shows the system picker (the app must be in front) and waits for the first frame.
    func start() async throws {
        #if canImport(ScreenCaptureKit) && !targetEnvironment(simulator)
        if capturing { return }
        guard !choosing, stream == nil else { throw ScreenError(message: "Screen sharing is already starting.") }
        guard UIApplication.shared.applicationState == .active else {
            throw ScreenError(message: "Open Mantiza to allow screen sharing.")
        }
        let id = UUID()
        generation = id
        note = ""
        latest = nil
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    selection = continuation
                    var config = SCContentSharingPickerConfiguration()
                    config.showsMicrophoneControl = false
                    picker.defaultConfiguration = config
                    picker.add(callbacks)
                    registered = true
                    choosing = true
                    picker.isActive = true
                    picker.present()
                }
            } onCancel: { Task { @MainActor [weak self] in if self?.generation == id { await self?.stop() } } }
            let deadline = Date().addingTimeInterval(5)
            while latest == nil {
                guard Date() < deadline else { throw ScreenError(message: "No screen image arrived. Try sharing again.") }
                try await Task.sleep(for: .milliseconds(20))
            }
            choosing = false
            Log.event("screen.start")
        } catch {
            await stop()
            throw error
        }
        #else
        throw ScreenError(message: "Screen capture needs a real iPhone.")
        #endif
    }

    func stop() async {
        choosing = false
        capturing = false
        latest = nil  // a stopped session must never hand an old screenshot to a later run
        #if canImport(ScreenCaptureKit)
        generation = nil
        output?.disable()
        output = nil
        let previous = stream
        stream = nil
        let continuation = selection
        selection = nil
        continuation?.resume(throwing: CancellationError())
        if registered { picker.isActive = false; picker.remove(callbacks); registered = false }
        try? await previous?.stopCapture()
        #endif
    }

    #if canImport(ScreenCaptureKit)
    fileprivate func selected(_ filter: SCContentFilter) async {
        guard choosing, stream == nil, let id = generation else { return }
        let receiver = CaptureOutput(publish: { [weak self] image, captured in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.frameID += 1
                self.latest = Frame(image: image, id: self.frameID, capturedAt: captured)
            }
        }, unavailable: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.latest = nil
            }
        })
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        let next = SCStream(filter: filter, configuration: config, delegate: callbacks)
        output = receiver
        stream = next
        do {
            try next.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
            try await next.startCapture()
            guard generation == id else { return }
            capturing = true
            let continuation = selection
            selection = nil
            continuation?.resume()
        } catch {
            await failed(error, stream: next)
        }
    }

    fileprivate func cancelledSelection() async {
        guard choosing, stream == nil else { return }  // cancelling a picker update keeps a running stream
        await stop()
    }

    fileprivate func failed(_ error: Error, stream stopped: SCStream? = nil) async {
        if let stopped, stream !== stopped { return }
        let message = error.localizedDescription
        let continuation = selection
        selection = nil
        continuation?.resume(throwing: error)
        await stop()
        note = message
        Log.event("screen.stopped", ["why": message])
        onStopped?(message)
    }
    #endif
}

#if canImport(ScreenCaptureKit)
private final class CaptureCallbacks: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, @unchecked Sendable {
    weak var owner: ScreenCaptureFeed?
    init(owner: ScreenCaptureFeed) { self.owner = owner }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in await self?.owner?.selected(filter) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in await self?.owner?.cancelledSelection() }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in await self?.owner?.failed(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in await self?.owner?.failed(error, stream: stream) }
    }
}

/// Converts samples on its own queue and drops extras rather than building a backlog.
private final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "screen.capture", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let publish: @Sendable (CGImage, Date) -> Void
    private let unavailable: @Sendable () -> Void
    private var wasUnavailable = false
    private var enabled = true
    private var last = -Double.infinity

    init(publish: @escaping @Sendable (CGImage, Date) -> Void, unavailable: @escaping @Sendable () -> Void) {
        self.publish = publish
        self.unavailable = unavailable
    }

    func disable() { queue.sync { enabled = false } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard enabled, type == .screen, sample.isValid else { return }
        let host = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first, let status = info[.status] as? Int else { return }
        if [SCFrameStatus.blank, .suspended, .stopped].contains(where: { $0.rawValue == status }) {
            if !wasUnavailable { unavailable() }
            wasUnavailable = true
            last = -Double.infinity
            return
        }
        guard status == SCFrameStatus.complete.rawValue || status == SCFrameStatus.started.rawValue else { return }
        wasUnavailable = false
        guard host - last >= 0.25, let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        last = host
        // displayTime is mach absolute time; map it onto the wall clock the actions use.
        var captured = Date()
        if let raw = info[.displayTime] as? NSNumber {
            let shown = CMClockMakeHostTimeFromSystemUnits(raw.uint64Value).seconds
            if shown.isFinite, shown > 0, shown <= host + 0.05 { captured = Date().addingTimeInterval(min(0, shown - host)) }
        }
        autoreleasepool {
            let input = CIImage(cvPixelBuffer: pixels)
            let scale = min(1, 960 / input.extent.width)
            let image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(image, from: image.extent) else { return }
            publish(cg, captured)
        }
    }
}
#endif
