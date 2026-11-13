import SwiftUI
import UIKit

/// The app's hands: turns screen points into device pointer moves.
///
/// The device moves the pointer in "counts" from the top-left corner ("tap x y" pushes it into
/// the corner first, then moves across and down in equal steps). Calibration finds how counts turn
/// into screen points on this phone, with this phone's tracking speed (test T4d: 4.37 pt per count
/// on an iPhone 14 Plus at the highest speed, 0 pt error). It works on any iPhone because it is
/// measured, not looked up.
@MainActor
final class Pointer: ObservableObject {
    weak var link: DeviceLink?
    weak var capture: ScreenCapture?

    // points = origin + counts × scale, per axis
    @Published private(set) var scaleX = UserDefaults.standard.double(forKey: "pointer.scaleX")
    @Published private(set) var scaleY = UserDefaults.standard.double(forKey: "pointer.scaleY")
    @Published private(set) var originX = UserDefaults.standard.double(forKey: "pointer.originX")
    @Published private(set) var originY = UserDefaults.standard.double(forKey: "pointer.originY")
    @Published var calibration = "Not calibrated"
    @Published var calibrating = false

    /// The device's pointer jumps to exact points: no calibration needed.
    var absolute: Bool { link?.absolute == true }
    var calibrated: Bool { absolute || (scaleX > 0 && scaleY > 0) }

    /// Calibration spots in counts. Small, so that at the highest tracking speed no click hits the
    /// screen edge (where the pointer stops and the measurement would be wrong). The third checks
    /// the first two.
    private let spots: [CGPoint] = [CGPoint(x: 20, y: 40), CGPoint(x: 50, y: 100), CGPoint(x: 35, y: 70)]
    private var caughtTaps: [CGPoint] = []

    init() {
        if calibrated { calibration = String(format: "1 count = %.2f × %.2f pt", scaleX, scaleY) }
    }

    private func note(_ text: String) { link?.note("[hands] \(text)") }

    // MARK: - Tap

    /// What "tap x y" needs for a screen point: 0…32767 across the screen with the absolute
    /// pointer, or counts from the corner (calibrated) with the old relative one.
    func counts(for point: CGPoint) -> (Int, Int)? {
        if absolute {
            let s = UIScreen.main.bounds.size
            let ax = Int((point.x / s.width * 32767).rounded())
            let ay = Int((point.y / s.height * 32767).rounded())
            return (min(max(ax, 0), 32767), min(max(ay, 0), 32767))
        }
        guard scaleX > 0, scaleY > 0 else { return nil }
        let cx = Int(((point.x - originX) / scaleX).rounded())
        let cy = Int(((point.y - originY) / scaleY).rounded())
        return (max(0, cx), max(0, cy))
    }

    /// Taps a screen point (in points). Returns false if it couldn't.
    func tap(_ point: CGPoint) async -> Bool {
        guard let link else { return false }
        // Never guess the pointer type: an unknown device would get the wrong kind of numbers.
        guard await link.confirmDevice() else { note("Can't tap: the device doesn't answer"); return false }
        guard let (cx, cy) = counts(for: point) else { note("Can't tap: not calibrated"); return false }
        let reply = await link.run("tap \(cx) \(cy)")
        return reply.hasPrefix("ok")
    }

    // MARK: - Calibration

    func startCalibration() {
        guard link?.ready == true else { calibration = "Device not connected"; return }
        caughtTaps = []
        calibrating = true
        calibration = "Calibrating… don't touch the screen"
        Task {
            try? await Task.sleep(for: .seconds(1))  // let the full-screen catcher appear
            for spot in spots {
                await link?.run("tap \(Int(spot.x)) \(Int(spot.y))")
                try? await Task.sleep(for: .milliseconds(700))
            }
            finishCalibration()
        }
    }

    /// Called by the full-screen catcher for every click that lands on it.
    func caught(_ point: CGPoint) {
        if calibrating { caughtTaps.append(point) }
    }

    private func finishCalibration() {
        calibrating = false
        guard caughtTaps.count == spots.count else {
            calibration = "Failed: caught \(caughtTaps.count) of \(spots.count) clicks. Is the pointer on? Try again."
            return
        }
        let screen = UIScreen.main.bounds.size
        if caughtTaps.contains(where: { $0.x >= screen.width - 15 || $0.y >= screen.height - 15 }) {
            calibration = "Failed: a click hit the screen edge. Try again."
            return
        }
        let (c1, c2, c3) = (spots[0], spots[1], spots[2])
        let (p1, p2, p3) = (caughtTaps[0], caughtTaps[1], caughtTaps[2])
        scaleX = (p2.x - p1.x) / (c2.x - c1.x)
        scaleY = (p2.y - p1.y) / (c2.y - c1.y)
        originX = p1.x - c1.x * scaleX
        originY = p1.y - c1.y * scaleY
        let predicted = CGPoint(x: originX + c3.x * scaleX, y: originY + c3.y * scaleY)
        let error = hypot(predicted.x - p3.x, predicted.y - p3.y)
        guard scaleX > 0, scaleY > 0, error < 25 else {
            calibration = String(format: "Failed: clicks didn't line up (check click %.0f pt off). Try again.", error)
            scaleX = 0; scaleY = 0
            return
        }
        for (k, v) in [("scaleX", scaleX), ("scaleY", scaleY), ("originX", originX), ("originY", originY)] {
            UserDefaults.standard.set(v, forKey: "pointer.\(k)")
        }
        calibration = String(format: "✅ 1 count = %.2f × %.2f pt · check click %.0f pt off", scaleX, scaleY, error)
        note(calibration)
    }

    // MARK: - Start screen sharing with no touch

    /// "Share Entire Screen" in Apple's picker: centred, 58% down (measured on the 14 Plus:
    /// 214, 538 of 428 × 926 pt). The panel is centred by iOS, so the fraction carries over to other
    /// screen sizes. (To do: measure it on each phone once capture is running.)
    private var pickerButton: CGPoint {
        let s = UIScreen.main.bounds.size
        return CGPoint(x: s.width / 2, y: s.height * 0.581)
    }

    /// Starts screen capture: shows the picker and lets the device press "Share Entire Screen".
    /// The app must be in front. Returns true once capture is on.
    func startSharing() async -> Bool {
        guard let capture else { return false }
        if capture.running { return true }
        guard calibrated else { note("Calibrate first (Device tab)"); return false }
        let before = capture.starts
        capture.showPicker()
        try? await Task.sleep(for: .seconds(2))
        _ = await tap(pickerButton)
        for i in 0..<16 {
            if capture.starts > before { return true }
            // Debug runs 2026-11-12_131937 and _132024: one press, no start. Press once more after
            // 3 s (the sheet may have been late), bringing Mantiza forward again if it went behind.
            if i == 6 {
                let front = UIApplication.shared.applicationState == .active
                note("Screen sharing: no start after the first press (Mantiza \(front ? "in front" : "behind"), \(capture.state)); pressing again")
                if !front { capture.showPicker(); try? await Task.sleep(for: .seconds(2)) }
                _ = await tap(pickerButton)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        note("Screen sharing didn't start (state: \(capture.state), Mantiza \(UIApplication.shared.applicationState == .active ? "in front" : "behind"))")
        return capture.starts > before
    }
}

/// Full-screen, see-through view that catches the device's calibration clicks.
struct CalibrationCatcher: View {
    @EnvironmentObject var pointer: Pointer

    var body: some View {
        ZStack {
            Color.yellow.opacity(0.15)
            VStack(spacing: 12) {
                Text("Calibrating").font(.title.bold())
                Text("The device clicks 3 spots. Don't touch the screen.")
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .global) { point in pointer.caught(point) }
    }
}
