import AVFoundation
import Speech

/// On-device English transcription of a finished recording (the stick's push-to-talk audio). No microphone or
/// audio session is involved, so it also works while Mantiza is in the background.
enum Transcriber {
    static func transcribe(_ audio: AVAudioPCMBuffer) async throws -> String {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()  // the English model, once
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converted = convert(audio, to: format) else {
            throw ScreenError(message: "Speech recognition is not available.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal { text += String(result.text.characters) }
            return text
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        input.yield(AnalyzerInput(buffer: converted))
        input.finish()
        try await analyzer.start(inputSequence: stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity:
                AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1024) else { return nil }
        var used = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if used { status.pointee = .endOfStream; return nil }
            used = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}
