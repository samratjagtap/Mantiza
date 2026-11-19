import Foundation
import Observation

/// Talking to the stick: hold A, speak, let go. The recording arrives on `audio`, is transcribed on the phone and
/// either answers a question the agent asked or becomes a new request (after a short window to cancel with B).
@MainActor @Observable final class StickTalk {
    static let cancelWindow = 2.0
    static let resendRounds = 3
    static let maxResend = 20

    let audio = StickAudio()
    private(set) var lastHeard = ""
    private(set) var transcribing = false
    /// A new request heard (and not cancelled).
    @ObservationIgnored var onRequest: ((String) -> Void)?
    /// The recording led nowhere (lost, not understood, empty, cancelled).
    @ObservationIgnored var onGaveUp: (() -> Void)?
    @ObservationIgnored private let channel: CommandChannel
    @ObservationIgnored private var waiter: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var waiterID = UUID()
    @ObservationIgnored private var cancelled = false

    init(channel: CommandChannel) { self.channel = channel }

    var waitingForAnswer: Bool { waiter != nil }

    func handle(_ event: BoardEvent) {
        switch event {
        case let .talkStart(utt):
            audio.begin(utt)
            Log.event("talk.start", ["utt": utt])
        case let .talkEnd(utt, packets):
            Task { await finish(utt, packets: packets) }
        case .b:
            cancelled = true
        case .talkShort:
            onGaveUp?()
        default: break
        }
    }

    /// Wait for the user's spoken answer to `question` (shown on the stick); nil after `timeout` seconds.
    func ask(_ question: String, timeout: Double = 90) async -> String? {
        waiter?.resume(returning: nil)
        try? await channel.send(.ui(.info, text: question + "|Hold A to answer"))
        let id = UUID()
        return await withCheckedContinuation { c in
            waiter = c
            waiterID = id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                if self?.waiterID == id { self?.answer(nil) }
            }
        }
    }

    private func answer(_ text: String?) {
        let w = waiter
        waiter = nil
        w?.resume(returning: text)
    }

    private func finish(_ utt: UInt32, packets: Int) async {
        guard utt == audio.utterance else { return }
        transcribing = true
        defer { transcribing = false }
        // Packets still in flight, then ask again for a few lost ones. Many lost means the audio channel itself
        // is not getting through, and asking packet by packet would take seconds for nothing.
        try? await Task.sleep(for: .milliseconds(250))
        Log.event("talk.received", ["utt": utt, "packets": packets, "arrived": audio.arrived, "unreadable": audio.unreadable,
                                    "missing": audio.missing(of: packets).count, "key": audio.key != nil])
        for _ in 0..<Self.resendRounds {
            let lost = audio.missing(of: packets)
            guard !lost.isEmpty, lost.count <= Self.maxResend, utt == audio.utterance else { break }
            for seq in lost { _ = try? await channel.send(.audio(utterance: utt, seq: seq)) }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard utt == audio.utterance else { return }  // a newer recording started meanwhile
        let missing = audio.missing(of: packets).count
        guard let buffer = audio.buffer(of: packets) else {
            Log.event("talk.lost", ["utt": utt, "missing": missing, "packets": packets])
            try? await channel.send(.ui(.error, text: "Didn't get that.|Hold A and try again."))
            onGaveUp?()
            return
        }
        let started = Date()
        let text: String
        do { text = try await Transcriber.transcribe(buffer) } catch {
            Log.event("talk.failed", ["error": error.localizedDescription])
            try? await channel.send(.ui(.error, text: "Couldn't understand.|\(error.localizedDescription)"))
            onGaveUp?()
            return
        }
        Log.event("talk.heard", ["utt": utt, "chars": text.count, "seconds": Double(packets) * 0.032,
                                 "ms": Int(Date().timeIntervalSince(started) * 1000)])
        lastHeard = text
        guard !text.isEmpty else {
            try? await channel.send(.ui(.error, text: "Didn't catch that.|Hold A and try again."))
            onGaveUp?()
            return
        }
        if waitingForAnswer {
            try? await channel.send(.ui(.info, text: "Got it:|" + text))
            answer(text)
            return
        }
        cancelled = false
        try? await channel.send(.ui(.info, text: "Heard: \(text)|B = cancel"))
        try? await Task.sleep(for: .seconds(Self.cancelWindow))
        if cancelled {
            try? await channel.send(.ui(.idle, text: ""))
            Log.event("talk.cancelled")
            onGaveUp?()
            return
        }
        onRequest?(text)
    }
}
