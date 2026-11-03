import AVFoundation
import CommonCrypto
import Foundation

/// Push-to-talk audio from the stick (firmware audio.h): encrypted IMA-ADPCM packets, one utterance at a time.
/// Packets are decrypted with the session's audio key, decoded to 16 kHz PCM and put in order; lost ones are
/// asked for again with `audio UTT SEQ` before the speech goes to the transcriber.
@MainActor final class StickAudio {
    nonisolated static let sampleRate = 16_000.0
    nonisolated static let header = 6

    /// AES-128 key of the authenticated session (SessionAuth.audioKey); nil drops all audio.
    var key: Data?
    private(set) var utterance: UInt32 = 0
    private var samples: [Int: [Int16]] = [:]
    /// For the log: packets that arrived, and those that could not be read (no key, too short).
    private(set) var arrived = 0
    private(set) var unreadable = 0

    func begin(_ utt: UInt32) {
        utterance = utt
        samples = [:]
        arrived = 0
        unreadable = 0
    }

    func receive(_ packet: Data) {
        arrived += 1
        guard let key, packet.count > Self.header,
              let plain = Self.decrypt(packet, key: key, utterance: utterance),
              let (seq, pcm) = Self.decode(plain) else { unreadable += 1; return }
        samples[seq] = pcm
    }

    func missing(of count: Int) -> [Int] { (0..<count).filter { samples[$0] == nil } }

    /// The utterance as one PCM buffer, once every packet is in.
    func buffer(of count: Int) -> AVAudioPCMBuffer? {
        guard count > 0, missing(of: count).isEmpty else { return nil }
        let all = (0..<count).flatMap { samples[$0]! }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(all.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(all.count)
        all.withUnsafeBufferPointer { buffer.int16ChannelData![0].update(from: $0.baseAddress!, count: all.count) }
        return buffer
    }

    // MARK: Packet format

    /// AES-128-CTR over everything after the 2-byte seq, IV = utterance u32 LE | seq u16 LE | 10 zero bytes.
    nonisolated static func decrypt(_ packet: Data, key: Data, utterance: UInt32) -> Data? {
        guard key.count == kCCKeySizeAES128, packet.count > 2 else { return nil }
        var iv = Data(count: 16)
        withUnsafeBytes(of: utterance.littleEndian) { iv.replaceSubrange(0..<4, with: $0) }
        iv.replaceSubrange(4..<6, with: packet.prefix(2))
        let body = packet.dropFirst(2)
        var out = Data(count: body.count)
        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { k in
            iv.withUnsafeBytes { v in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                        CCPadding(ccNoPadding), v.baseAddress, k.baseAddress, key.count, nil, 0, 0,
                                        CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
            }
        }
        guard created == kCCSuccess, let cryptor else { return nil }
        defer { CCCryptorRelease(cryptor) }
        var moved = 0
        let status = body.withUnsafeBytes { b in
            out.withUnsafeMutableBytes { o in
                CCCryptorUpdate(cryptor, b.baseAddress, body.count, o.baseAddress, body.count, &moved)
            }
        }
        guard status == kCCSuccess, moved == body.count else { return nil }
        return packet.prefix(2) + out
    }

    nonisolated private static let steps: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
        107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
        4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
        22385, 24623, 27086, 29794, 32767,
    ]
    nonisolated private static let indexAdjust = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    /// seq and samples of one plain packet: seq u16 | predictor i16 | step index u8 | 0 | ADPCM, low nibble first.
    nonisolated static func decode(_ packet: Data) -> (Int, [Int16])? {
        let p = [UInt8](packet)
        guard p.count >= header else { return nil }
        let seq = Int(p[0]) | Int(p[1]) << 8
        var predictor = Int(Int16(bitPattern: UInt16(p[2]) | UInt16(p[3]) << 8))
        var index = min(Int(p[4]), 88)
        var out: [Int16] = []
        out.reserveCapacity((p.count - header) * 2)
        for byte in p[header...] {
            for code in [Int(byte & 15), Int(byte >> 4)] {
                let step = steps[index]
                var delta = step >> 3
                if code & 4 != 0 { delta += step }
                if code & 2 != 0 { delta += step >> 1 }
                if code & 1 != 0 { delta += step >> 2 }
                predictor = min(max(code & 8 != 0 ? predictor - delta : predictor + delta, -32768), 32767)
                index = min(max(index + indexAdjust[code], 0), 88)
                out.append(Int16(predictor))
            }
        }
        return (seq, out)
    }
}
