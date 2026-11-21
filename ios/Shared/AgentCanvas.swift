import Foundation
import WidgetKit

/// What the full-screen agent widget shows: the session, what the agent heard and is doing, its last steps, the
/// screen it last saw, and a result card written by the AI. Written by the app into the App Group container.
struct AgentCanvas: Codable, Equatable {
    static let kind = "agent-canvas"

    enum Phase: String, Codable {
        case idle, listening, working, waiting, done, failed

        var title: String {
            switch self {
            case .idle: return "Ready"
            case .listening: return "Listening"
            case .working: return "Working"
            case .waiting: return "Needs you"
            case .done: return "Done"
            case .failed: return "Stopped"
            }
        }
    }

    struct Step: Codable, Equatable, Identifiable {
        var id: Int
        var text: String
    }

    /// The AI's summary of a finished task, e.g. "Order placed" / "Chipotle bowl, arrives 7:40".
    struct Card: Codable, Equatable {
        var headline: String
        var detail: String
        /// An SF Symbol name.
        var symbol: String
    }

    var phase = Phase.idle
    var session = false
    var request = ""
    var status = ""
    var step = 0
    var total = 0
    var steps: [Step] = []
    var card: Card?
    var question: String?
    var suggestions: [WidgetSnapshot.Item] = []
    var updated = Date()

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.group) }
    static var thumbnailURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appending(path: "canvas.jpg")
    }

    static func load() -> AgentCanvas {
        guard let data = defaults?.data(forKey: "canvas"),
              let c = try? JSONDecoder().decode(AgentCanvas.self, from: data) else { return AgentCanvas() }
        return c
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Self.defaults?.set(data, forKey: "canvas") }
    }

    static let sessionURL = URL(string: "mantiza://session")!
}
