import Foundation

/// What Siri, a Control Centre button, the Live Activity or the widget asks the app to do. The
/// actions (App Intents) post a command here; the app picks it up as soon as it is running.
public enum Command: Equatable, Sendable {
    case run(String)   // do this task
    case listen        // open ready to listen (voice)
    case stop          // stop the running task
}

@MainActor
public final class Inbox: ObservableObject {
    public static let shared = Inbox()
    /// Counts up with every command, so the same command twice is still seen as new.
    @Published public private(set) var count = 0
    public private(set) var command: Command?

    public func post(_ c: Command) {
        command = c
        count += 1
    }

    /// The waiting command, handed out once.
    public func take() -> Command? {
        defer { command = nil }
        return command
    }
}
