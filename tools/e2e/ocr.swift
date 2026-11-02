// Prints the text on an image as JSON lines {"text", "x", "y"} (centre, fractions from the top-left).
// Usage: swift tools/e2e/ocr.swift screenshot.png
import Foundation
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
try VNImageRequestHandler(url: url).perform([request])
for o in request.results ?? [] {
    guard let text = o.topCandidates(1).first?.string else { continue }
    let b = o.boundingBox
    let line: [String: Any] = ["text": text, "x": Double(b.midX), "y": Double(1 - b.midY)]
    print(String(data: try JSONSerialization.data(withJSONObject: line), encoding: .utf8)!)
}
