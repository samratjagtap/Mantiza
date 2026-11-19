import AVFoundation
import Observation
import Speech

/// Push-to-talk: on-device English transcription with SpeechAnalyzer. `text` grows while you speak.
@MainActor @Observable final class VoiceInput {
    private(set) var listening = false
    private(set) var text = ""
    private(set) var error = ""

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var finalText = ""

    func start() async {
        guard !listening else { return }
        error = ""
        text = ""
        finalText = ""
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow the microphone for Mantiza in Settings."
            return
        }
        do {
            let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .progressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()  // the English model, once
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw ScreenError(message: "Speech recognition is not available.")
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            input = continuation
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let piece = String(result.text.characters)
                        await MainActor.run {
                            guard let self else { return }
                            if result.isFinal { self.finalText += piece; self.text = self.finalText } else {
                                self.text = self.finalText + piece
                            }
                        }
                    }
                } catch {}
            }
            try await analyzer.start(inputSequence: stream)

            let engine = AVAudioEngine()
            let mic = engine.inputNode.outputFormat(forBus: 0)
            let converter = AVAudioConverter(from: mic, to: format)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: mic) { buffer, _ in
                guard let converter, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity:
                    AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / mic.sampleRate) + 1) else { return }
                var used = false
                converter.convert(to: out, error: nil) { _, status in
                    if used { status.pointee = .noDataNow; return nil }
                    used = true
                    status.pointee = .haveData
                    return buffer
                }
                continuation.yield(AnalyzerInput(buffer: out))
            }
            try engine.start()
            self.engine = engine
            listening = true
            Log.event("voice.start")
        } catch {
            self.error = error.localizedDescription
            await stop()
        }
    }

    /// Stop listening and wait for the last words. Returns the full transcript.
    @discardableResult
    func stop() async -> String {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        try? await Task.sleep(for: .milliseconds(150))
        resultsTask?.cancel()
        resultsTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if listening { Log.event("voice.stop", ["chars": text.count]) }
        listening = false
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpeechTranscriber.Result {
    /// Final results are no longer revised.
    var isFinal: Bool { resultsFinalizationTime >= range.end }
}
