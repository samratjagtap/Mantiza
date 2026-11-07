import AVFoundation
import Foundation
import UIKit

/// Phone settings the app can read straight from iOS, so a task can be checked exactly (and stop
/// at once) instead of judging from a screenshot. iOS doesn't let apps read Wi-Fi, Airplane mode
/// or rotation lock; those are checked by the fast brain from the screen.
enum PhoneState {
    /// Names the planner may use in a subtask's "state".
    static let names = ["flashlight", "low_power_mode", "dark_mode"]

    /// The current value, or nil if this setting can't be read.
    @MainActor
    static func read(_ name: String) -> Bool? {
        switch name {
        case "flashlight":
            guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else { return nil }
            return camera.isTorchActive
        case "low_power_mode":
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        case "dark_mode":
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            guard let style = scene?.traitCollection.userInterfaceStyle, style != .unspecified else { return nil }
            return style == .dark
        default:
            return nil
        }
    }
}
