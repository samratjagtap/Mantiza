import CoreGraphics
import Foundation
import Vision

/// Reads the text on a screen image on the device (Apple Vision), in reading order.
enum OCR {
    /// The top strip (clock, Dynamic Island) is not content.
    static let statusBar = 0.055

    static func read(_ frame: Frame, ignore: [CGRect] = []) async throws -> ScreenReading {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: frame.image)
        var items: [(text: String, box: CGRect, confidence: Double)] = []
        for o in observations {
            guard let best = o.topCandidates(1).first else { continue }
            let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let r = o.boundingBox  // normalized, bottom-left origin
            let box = CGRect(x: r.origin.x, y: 1 - r.origin.y - r.height, width: r.width, height: r.height)
            if text.isEmpty || box.midY < statusBar || ignore.contains(where: { $0.contains(CGPoint(x: box.midX, y: box.midY)) }) {
                continue
            }
            items.append((text, box, Double(best.confidence)))
        }
        return ScreenReading(frameID: frame.id, elements: ordered(items))
    }

    /// Top to bottom, then left to right within a line (boxes whose centres are within half a line height).
    static func ordered(_ items: [(text: String, box: CGRect, confidence: Double)]) -> [ScreenElement] {
        let sorted = items.sorted { $0.box.midY < $1.box.midY }
        var lines: [[(text: String, box: CGRect, confidence: Double)]] = []
        for item in sorted {
            if let last = lines.last?.first, abs(last.box.midY - item.box.midY) < max(last.box.height, item.box.height) / 2 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        return lines.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }.enumerated().map { i, item in
            ScreenElement(id: i + 1, text: item.text, box: item.box, confidence: item.confidence)
        }
    }
}
