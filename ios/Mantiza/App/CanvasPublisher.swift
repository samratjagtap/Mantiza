import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Keeps the full-screen agent widget current. WidgetKit budgets reloads, so changes are saved at once but the
/// widget is reloaded at most every `minInterval` seconds (milestones like done or a question go out at once).
@MainActor final class CanvasPublisher {
    static let minInterval = 2.0
    static let thumbnailWidth = 400

    private(set) var canvas = AgentCanvas.load()
    private var lastReload = Date.distantPast
    private var pending: Task<Void, Never>?

    func update(now: Bool = false, thumbnail: Frame? = nil, _ change: (inout AgentCanvas) -> Void) {
        var next = canvas
        change(&next)
        next.updated = Date()
        canvas = next
        canvas.save()
        if let thumbnail { Self.saveThumbnail(thumbnail) }
        let wait = Self.minInterval - Date().timeIntervalSince(lastReload)
        if now || wait <= 0 {
            reload()
        } else if pending == nil {
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                self?.reload()
            }
        }
    }

    private func reload() {
        pending?.cancel()
        pending = nil
        lastReload = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: AgentCanvas.kind)
        Log.event("canvas.reload", ["phase": canvas.phase.rawValue, "step": canvas.step])
    }

    /// The screen the agent last saw, small enough for the widget's memory limit.
    private static func saveThumbnail(_ frame: Frame) {
        guard let url = AgentCanvas.thumbnailURL, let jpeg = frame.jpeg(quality: 0.6, maxWidth: thumbnailWidth) else { return }
        try? jpeg.write(to: url, options: .atomic)
    }
}
