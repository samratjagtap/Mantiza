#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity for a running task: what Mantiza is doing, on the Lock Screen and in the
/// Dynamic Island, while another app is in front. Shared by the app (which starts and updates it)
/// and the widget (which draws it).
public struct TaskActivity: ActivityAttributes {
    public enum Phase: String, Codable, Sendable {
        case working   // doing steps
        case asking    // waiting for the user's OK or a choice
        case done, failed, stopped
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String   // "Step 3: tapping Search"
        public var phase: Phase
        public init(status: String, phase: Phase) {
            self.status = status
            self.phase = phase
        }
    }

    /// What the user asked for.
    public var request: String
    public init(request: String) { self.request = request }
}
#endif
