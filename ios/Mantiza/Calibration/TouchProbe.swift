import SwiftUI
import UIKit

// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo fork, MIT); see THIRD_PARTY_NOTICES.md.

/// Records where the stick's taps land on this app's own screen during calibration, as screen fractions.
@MainActor @Observable final class TouchProbe {
    private(set) var hits: [CGPoint] = []
    @ObservationIgnored private var taps: [(time: Date, at: CGPoint)] = []

    func reset() {
        taps = []
        hits = []
    }

    fileprivate func touched(_ p: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        record(CGPoint(x: p.x / size.width, y: p.y / size.height))
    }

    /// A tap landed at screen fraction `f` (tests call this directly).
    func record(_ f: CGPoint) {
        taps.append((Date(), f))
        hits = Array((hits + [f]).suffix(20))
    }

    /// The first tap after `since` (when the tap was sent), waiting up to `timeout` seconds.
    func tap(since: Date, timeout: Double = 3) async -> CGPoint? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            if let hit = taps.first(where: { $0.time >= since }) {
                taps.removeAll { $0.time <= hit.time }
                return hit.at
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}

/// A full-screen view that reports where each touch begins, in screen points with the screen's size.
struct TouchCatcherView: UIViewRepresentable {
    let probe: TouchProbe

    func makeUIView(context: Context) -> TouchCatcher {
        let view = TouchCatcher()
        view.onTouch = { [weak probe] p, size in probe?.touched(p, in: size) }
        return view
    }

    func updateUIView(_ view: TouchCatcher, context: Context) {}
}

final class TouchCatcher: UIView {
    var onTouch: ((CGPoint, CGSize) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let screen = window?.windowScene?.screen {
                onTouch?(convert(t.location(in: self), to: screen.coordinateSpace), screen.bounds.size)
            } else {
                onTouch?(t.location(in: self), bounds.size)
            }
        }
    }
}
