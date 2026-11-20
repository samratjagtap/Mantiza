import AVFoundation
import Speech
import SwiftUI

// Mantiza's voice: it says the result out loud (Apple's built-in voice: free, on the phone), and
// it listens (Apple's speech recognition, on the phone where the iPhone supports it).

// MARK: - Speaking

/// When Mantiza speaks its result.
enum SpeakMode: String, CaseIterable, Identifiable {
    case voice    // only when the task was asked by voice (like Siri's automatic setting)
    case always
    case never
    var id: String { rawValue }
    /// For the settings row (one line).
    var short: String {
        switch self {
        case .voice: return "By voice"
        case .always: return "Always"
        case .never: return "Never"
        }
    }

    var label: String {
        switch self {
        case .voice: return "When I ask by voice"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Voice()

    @Published var mode = SpeakMode(rawValue: UserDefaults.standard.string(forKey: "speak.mode") ?? "") ?? .voice {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "speak.mode") }
    }
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaking now, or about to (waiting for the result sound to finish).
    var speaking: Bool { synth.isSpeaking || waiting }
    private var waiting = false

    /// Says a task's result, if the setting allows it, `after` seconds (the result sound first).
    func say(result status: String, reply: String, askedByVoice: Bool, after: Double = 0) {
        guard mode == .always || (mode == .voice && askedByVoice) else { return }
        guard let text = Voice.spoken(status: status, reply: reply) else { return }
        guard after > 0 else { speak(text); return }
        waiting = true
        Task {
            try? await Task.sleep(for: .seconds(after))
            waiting = false
            speak(text)
        }
    }

    func speak(_ text: String) {
        // Speech plays over other audio, which gets quieter for a moment (ducking), also while
        // another app is in front (the "audio" background mode). Like Siri, it is heard even when
        // the ring switch is on silent: that is why the default is "when I ask by voice".
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Voice.best()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Give the sound back to whatever was playing.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The best voice installed for the phone's language: premium, then enhanced, then standard.
    /// (Better voices are a free download in Settings → Accessibility → Read & Speak → Voices.)
    private static func best() -> AVSpeechSynthesisVoice? {
        let language = Locale.preferredLanguages.first ?? "en-US"
        let base = String(language.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(base) }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            (v.quality == .premium ? 4 : v.quality == .enhanced ? 2 : 0) + (v.language == language ? 1 : 0)
        }
        return voices.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    /// What to say for a finished task: the answer or a short confirmation, never the log details.
    static func spoken(status: String, reply: String) -> String? {
        func clean(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)  // (details)
            t = t.replacingOccurrences(of: "·", with: ".")
            t = String(t.unicodeScalars.filter { !$0.properties.isEmojiPresentation && $0 != "\u{FE0F}" })
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status.hasPrefix("✅") {
            let text = clean(reply)
            return text.isEmpty ? "Done." : text
        }
        if status.hasPrefix("💬") { return clean(String(status.dropFirst())) }
        if status.hasPrefix("❓") || status.hasPrefix("⛔") { return clean(String(status.dropFirst())) }
        if status.hasPrefix("❌") {
            let why = clean(String(status.dropFirst())).split(separator: ":").first.map(String.init) ?? ""
            return "Sorry, that didn't work. " + why
        }
        return nil  // stopped by the user: nothing to say
    }
}

// MARK: - Listening

/// Turns speech into the request text. Stops by itself when you stop talking, then hands the text
/// over to be run.
@MainActor
final class Listener: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published var problem: String?

    /// Called with the final text when listening ends with something said.
    var onDone: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var watchdog: Task<Void, Never>?
    private var lastHeardAt = Date()

    func toggle() {
        if listening { finish(run: true) } else { Task { await start() } }
    }

    func start() async {
        guard !listening else { return }
        problem = nil
        heard = ""
        guard await Listener.allowed() else {
            problem = "Allow Microphone and Speech Recognition for Mantiza in iPhone Settings."
            return
        }
        let preferred = Locale(identifier: Locale.preferredLanguages.first ?? "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: preferred) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            problem = "Speech recognition isn't available right now."
            return
        }
        Voice.shared.stopSpeaking()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.taskHint = .dictation
            // On the phone when it can: faster, private, works without internet.
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.listening else { return }
                    if let text, text != self.heard {
                        self.heard = text
                        self.lastHeardAt = Date()
                    }
                    if final || error != nil { self.finish(run: true) }
                }
            }
            listening = true
            lastHeardAt = Date()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Stop 1.5 s after the last word; give up after 7 s of nothing.
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, self.listening else { return }
                    let quiet = Date().timeIntervalSince(self.lastHeardAt)
                    if (!self.heard.isEmpty && quiet > 1.5) || quiet > 7 { self.finish(run: true); return }
                }
            }
        } catch {
            problem = "The microphone couldn't start: \(error.localizedDescription)"
            finish(run: false)
        }
    }

    /// Stops listening. `run`: hand over what was heard.
    func finish(run: Bool) {
        guard listening || request != nil else { return }
        listening = false
        watchdog?.cancel()
        watchdog = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if run, !text.isEmpty {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDone?(text)
        }
    }

    private static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
