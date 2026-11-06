import SwiftUI
import UIKit

/// T4d: start screen sharing with no touch on the phone.
/// The device opens this app (Search) and sends "share". The app shows the picker and
/// tells the device where to click ("tap x y"), so the device presses the share button.
///
/// The device moves the pointer in "counts" from the top-left corner. Calibration finds
/// how counts turn into screen points: the device clicks known counts, this app sees
/// where the clicks land.
@MainActor
final class ShareByDevice: ObservableObject {
    weak var link: DeviceLink?
    weak var capture: ScreenCapture?

    // points = origin + counts × scale (per axis)
    @Published var scaleX = UserDefaults.standard.double(forKey: "t4d.scaleX")
    @Published var scaleY = UserDefaults.standard.double(forKey: "t4d.scaleY")
    @Published var originX = UserDefaults.standard.double(forKey: "t4d.originX")
    @Published var originY = UserDefaults.standard.double(forKey: "t4d.originY")
    @Published var calibration = "Not calibrated"
    @Published var calibrating = false

    /// Where the picker's share button is, in screen points (from a screenshot ÷ 3).
    @Published var buttonX = UserDefaults.standard.string(forKey: "t4d.buttonX") ?? ""
    @Published var buttonY = UserDefaults.standard.string(forKey: "t4d.buttonY") ?? ""
    @Published var waitBeforeClick = UserDefaults.standard.object(forKey: "t4d.wait") as? Double ?? 2.0

    @Published var lastResult = "–"
    @Published var tries = 0
    @Published var successes = 0

    /// The three calibration spots, in counts. The third one checks the first two.
    /// Small on purpose: at the highest tracking speed bigger moves can hit the screen
    /// edge, where the pointer stops and the measurement would be wrong.
    let spots: [CGPoint] = [CGPoint(x: 20, y: 40), CGPoint(x: 50, y: 100), CGPoint(x: 35, y: 70)]
    private var taps: [CGPoint] = []

    init() {
        if scaleX != 0, scaleY != 0 { calibration = String(format: "Saved: 1 count = %.2f × %.2f pt", scaleX, scaleY) }
    }

    private func note(_ text: String) { link?.note("[t4d] \(text)") }

    // MARK: - Calibration

    func startCalibration() {
        guard link?.ready == true else { calibration = "Device not ready (T2 tab → Connect again)"; return }
        taps = []
        calibrating = true
        calibration = "Calibrating… don't touch the screen"
        Task {
            try? await Task.sleep(for: .seconds(1))  // let the full-screen catcher appear
            for spot in spots {
                link?.send("tap \(Int(spot.x)) \(Int(spot.y))")
                try? await Task.sleep(for: .seconds(3))
            }
            finishCalibration()
        }
    }

    /// Called by the full-screen catcher for every click that lands on it.
    func caught(_ point: CGPoint) {
        guard calibrating else { return }
        taps.append(point)
        note(String(format: "Calibration click %d landed at %.0f, %.0f pt", taps.count, point.x, point.y))
    }

    private func finishCalibration() {
        calibrating = false
        guard taps.count == spots.count else {
            calibration = "Failed: caught \(taps.count) of \(spots.count) clicks. Is the pointer on? Try again."
            note(calibration)
            return
        }
        let screen = UIScreen.main.bounds.size
        if let edge = taps.first(where: { $0.x >= screen.width - 15 || $0.y >= screen.height - 15 }) {
            calibration = String(format: "Failed: a click hit the screen edge (%.0f, %.0f). Lower the tracking speed a little and try again.", edge.x, edge.y)
            note(calibration)
            return
        }
        let (c1, c2, c3) = (spots[0], spots[1], spots[2])
        let (p1, p2, p3) = (taps[0], taps[1], taps[2])
        scaleX = (p2.x - p1.x) / (c2.x - c1.x)
        scaleY = (p2.y - p1.y) / (c2.y - c1.y)
        originX = p1.x - c1.x * scaleX
        originY = p1.y - c1.y * scaleY
        let predicted = CGPoint(x: originX + c3.x * scaleX, y: originY + c3.y * scaleY)
        let error = hypot(predicted.x - p3.x, predicted.y - p3.y)
        for (k, v) in [("scaleX", scaleX), ("scaleY", scaleY), ("originX", originX), ("originY", originY)] {
            UserDefaults.standard.set(v, forKey: "t4d.\(k)")
        }
        let landed = taps.map { String(format: "%.0f,%.0f", $0.x, $0.y) }.joined(separator: " · ")
        calibration = String(format: "1 count = %.2f × %.2f pt · check click off by %.0f pt\nClicks: ", scaleX, scaleY, error) + landed
        note(calibration)
    }

    // MARK: - Share

    func saveButton() {
        UserDefaults.standard.set(buttonX, forKey: "t4d.buttonX")
        UserDefaults.standard.set(buttonY, forKey: "t4d.buttonY")
        UserDefaults.standard.set(waitBeforeClick, forKey: "t4d.wait")
    }

    /// The button spot in device counts, or nil if something is missing.
    private var buttonCounts: (Int, Int)? {
        guard scaleX != 0, scaleY != 0, let px = Double(buttonX), let py = Double(buttonY) else { return nil }
        return (Int(((px - originX) / scaleX).rounded()), Int(((py - originY) / scaleY).rounded()))
    }

    /// Runs when the device sends "share", or from the button in the app.
    func share(fromDevice: Bool) {
        guard let capture, let link else { return }
        let front = UIApplication.shared.applicationState == .active
        note("Share asked by the \(fromDevice ? "device" : "app"); app is \(front ? "in front" : "NOT in front")")
        if capture.running {
            lastResult = "Already capturing"
            link.send("shared already")
            return
        }
        guard let (cx, cy) = buttonCounts else {
            lastResult = "Calibrate and enter the button spot first"
            link.send("shared not-set-up")
            return
        }
        tries += 1
        let asked = Date()
        let startsBefore = capture.starts
        capture.startWithPicker()
        Task {
            try? await Task.sleep(for: .seconds(waitBeforeClick))
            note("Asking the device to click the share button at \(cx), \(cy) counts")
            link.send("tap \(cx) \(cy)")
            // Wait up to 8 s for the capture to start.
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(500))
                if capture.starts > startsBefore { break }
            }
            if capture.starts > startsBefore {
                successes += 1
                let s = Date().timeIntervalSince(asked)
                lastResult = String(format: "✅ Capturing, %.1f s after the ask", s)
                link.send(String(format: "shared ok %.1fs", s))
            } else {
                lastResult = "❌ Capture did not start (state: \(capture.state))"
                link.send("shared fail")
            }
            note(lastResult)
        }
    }
}

/// Full-screen, see-through view that catches the device's calibration clicks.
struct CalibrationCatcher: View {
    @EnvironmentObject var share: ShareByDevice

    var body: some View {
        ZStack {
            Color.yellow.opacity(0.15)
            VStack(spacing: 12) {
                Text("Calibrating").font(.title.bold())
                Text("The device clicks 3 spots. Don't touch the screen.")
                Text("Clicks caught: \(share.calibrating ? "…" : "done")")
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .global) { point in share.caught(point) }
    }
}
