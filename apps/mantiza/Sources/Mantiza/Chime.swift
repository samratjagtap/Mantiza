import AVFoundation
import UIKit

/// A soft sound when a task ends, so you know without looking: two rising notes when it worked,
/// two lower falling notes when it didn't. Nothing when you stopped it yourself. Made here from sine
/// waves (no sound files), played over other audio without pausing it, also while another app is in
/// front (the "audio" background mode). A light tap of haptics too when Mantiza is on screen.
@MainActor
final class Chime: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Chime()

    enum Kind { case done, failed }

    @Published var on = UserDefaults.standard.object(forKey: "sounds.on") as? Bool ?? true {
        didSet { UserDefaults.standard.set(on, forKey: "sounds.on") }
    }

    private var player: AVAudioPlayer?
    private lazy var sounds: [Kind: Data] = [
        // C6 → G6: light and short.
        .done: Chime.wav(notes: [(1046.5, 0.0), (1568.0, 0.11)], length: 0.55, volume: 0.32),
        // E5 → B4: lower and a little longer, still soft.
        .failed: Chime.wav(notes: [(659.3, 0.0), (493.9, 0.16)], length: 0.7, volume: 0.34),
    ]

    /// How a status line ends a task: done (✅, 💬), failed (❌, ⛔, ❓), or nil (stopped by you).
    static func kind(of status: String) -> Kind? {
        if status.hasPrefix("✅") || status.hasPrefix("💬") { return .done }
        if status.hasPrefix("❌") || status.hasPrefix("⛔") || status.hasPrefix("❓") { return .failed }
        return nil
    }

    /// Plays the sound for this result. Returns how long to wait before speaking (0 if nothing played).
    @discardableResult
    func play(result status: String) -> Double {
        guard let kind = Chime.kind(of: status) else { return 0 }
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(kind == .done ? .success : .error)
        }
        guard on, let data = sounds[kind] else { return 0 }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let p = try? AVAudioPlayer(data: data) else { return 0 }
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        return p.duration * 0.8
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Give the sound back to whatever was playing, unless Mantiza is about to speak.
            if !Voice.shared.speaking {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    // MARK: - Making the sound

    /// A 16-bit mono WAV: each note a sine with a soft overtone, a quick fade-in and a gentle decay.
    private static func wav(notes: [(freq: Double, start: Double)], length: Double, volume: Double) -> Data {
        let rate = 44_100.0
        let count = Int(rate * length)
        var samples = [Double](repeating: 0, count: count)
        for note in notes {
            let first = Int(note.start * rate)
            for i in first..<count {
                let t = Double(i - first) / rate
                let attack = min(1, t / 0.008)                 // 8 ms fade-in: no click
                let decay = exp(-t * 7.5)                      // rings out softly
                let wave = sin(2 * .pi * note.freq * t) + 0.18 * sin(4 * .pi * note.freq * t)
                samples[i] += wave * attack * decay
            }
        }
        // The end fades to silence over the last 60 ms.
        let fade = Int(0.06 * rate)
        for k in 0..<fade { samples[count - 1 - k] *= Double(k) / Double(fade) }
        let peak = samples.map(abs).max() ?? 1
        let scale = volume / max(peak, 0.0001) * 32_767

        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let bytes = count * 2
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        for s in samples { put(Int16(max(-32_767, min(32_767, s * scale)))) }
        return data
    }
}
