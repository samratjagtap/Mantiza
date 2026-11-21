import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One captured screen image. Coordinates everywhere are screen fractions with a top-left origin.
struct Frame: @unchecked Sendable {
    let image: CGImage
    let id: Int
    let capturedAt: Date

    var size: CGSize { CGSize(width: image.width, height: image.height) }

    /// JPEG for the vision models (re-encoded on each call; callers keep the result).
    func jpeg(quality: Double = 0.7, maxWidth: Int = 960) -> Data? {
        var img = image
        if img.width > maxWidth, let scaled = Self.scaled(img, width: maxWidth) { img = scaled }
        let bytes = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? bytes as Data : nil
    }

    static func scaled(_ img: CGImage, width: Int) -> CGImage? {
        let height = Int((Double(img.height) * Double(width) / Double(img.width)).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// A piece of text read from the screen.
struct ScreenElement: Equatable, Codable, Identifiable {
    var id: Int
    var text: String
    /// Screen fractions, top-left origin.
    var box: CGRect
    var confidence: Double = 1

    var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
}

/// What the eyes saw on one frame.
struct ScreenReading: Equatable {
    var frameID: Int
    var elements: [ScreenElement]

    /// Compact table for the models: one row per element, positions in thousandths of the screen.
    var table: String {
        elements.map { e in
            "\(e.id) | \(e.text) | \(Int(e.center.x * 1000)),\(Int(e.center.y * 1000))"
        }.joined(separator: "\n")
    }

    /// All text in reading order, for verification and safety checks.
    var allText: String { elements.map(\.text).joined(separator: "\n") }

    func element(_ id: Int) -> ScreenElement? { elements.first { $0.id == id } }

    /// Elements whose text matches `query` (case-insensitive): exact matches first, then containing ones.
    func find(_ query: String) -> [ScreenElement] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let exact = elements.filter { $0.text.lowercased() == q }
        return exact + elements.filter { $0.text.lowercased().contains(q) && $0.text.lowercased() != q }
    }
}
