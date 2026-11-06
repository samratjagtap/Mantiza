import CoreGraphics
import UIKit
import Vision

/// A piece of text on the screen and where it is, in pixels of the captured frame (top-left origin).
struct ScreenItem: Identifiable {
    let number: Int
    let text: String
    let box: CGRect
    var id: Int { number }
    var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
}

/// Reads the screen with Apple's on-phone text recognition (Vision). Free, private, no network.
enum ScreenReader {
    /// All text lines on the frame, numbered from top to bottom. The status bar (clock, battery) is
    /// left out.
    static func read(_ image: CGImage) async -> [ScreenItem] {
        await Task.detached(priority: .userInitiated) { () -> [ScreenItem] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let boxes: [(String, CGRect)] = (request.results ?? []).compactMap { obs in
                guard let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                      !text.isEmpty else { return nil }
                let b = obs.boundingBox  // normalised, bottom-left origin
                let rect = CGRect(x: b.minX * w, y: (1 - b.maxY) * h, width: b.width * w, height: b.height * h)
                if rect.maxY < h * 0.055 { return nil }  // status bar
                return (text, rect)
            }
            // Top to bottom, then left to right (rows within 1% of the height count as one row).
            let sorted = boxes.sorted {
                abs($0.1.minY - $1.1.minY) < h * 0.01 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY
            }
            return sorted.prefix(60).enumerated().map { ScreenItem(number: $0 + 1, text: $1.0, box: $1.1) }
        }.value
    }
}

/// Screenshot pictures for the brains.
enum Marks {
    /// The frame with a pink numbered box around every text item (numbers sit just above the box,
    /// never over it), as JPEG.
    static func numbered(_ image: CGImage, items: [ScreenItem]) -> Data? {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let pink = UIColor(red: 1, green: 0, blue: 0.78, alpha: 1)
        let font = UIFont.boldSystemFont(ofSize: max(14, size.width / 34))
        let picture = renderer.image { ctx in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setStrokeColor(pink.cgColor)
            cg.setLineWidth(2)
            for item in items {
                cg.stroke(item.box.insetBy(dx: -2, dy: -2))
                let label = "\(item.number)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let ts = label.size(withAttributes: attrs)
                var tag = CGRect(x: item.box.minX - 2, y: item.box.minY - ts.height - 2, width: ts.width + 6, height: ts.height)
                if tag.minY < 0 { tag.origin.y = item.box.maxY + 2 }
                pink.setFill()
                UIRectFill(tag)
                label.draw(at: CGPoint(x: tag.minX + 3, y: tag.minY), withAttributes: attrs)
            }
        }
        return picture.jpegData(compressionQuality: 0.7)
    }

    static func plain(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }
}
