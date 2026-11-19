import AppIntents
import Foundation

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Siri, Shortcuts and Control Center → the app. The intents run in the app's process; AppModel sets `handle`.
@MainActor enum WorkflowRequests {
    /// Runs the workflow with this id (nil: the current suggestion) and returns the line to say or show.
    static var handle: ((String?) async -> String)?
    nonisolated static var unavailable: String { "Open Mantiza once, then try again." }
}

/// A saved workflow, as Siri and Shortcuts see it.
struct WorkflowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workflow"
    static let defaultQuery = WorkflowQuery()

    let id: String
    let name: String
    let app: String?

    init(_ item: WidgetSnapshot.Item) {
        id = item.id
        name = item.name
        app = item.app
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: app.map { "\($0)" }, image: .init(systemName: "hand.tap"))
    }
}

struct WorkflowQuery: EntityStringQuery {
    private var items: [WorkflowEntity] { WidgetSnapshot.load().all.map(WorkflowEntity.init) }

    func entities(for identifiers: [String]) async throws -> [WorkflowEntity] {
        items.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WorkflowEntity] {
        items.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WorkflowEntity] { items }
}

/// Runs a saved workflow. A LiveActivityIntent, so it runs in the app's process and may start the Live
/// Activity from the background (the session's screen sharing must already be on).
struct RunWorkflowIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Run a Mantiza Workflow"
    static let description = IntentDescription("Runs one of your saved Mantiza workflows on this iPhone.")

    @Parameter(title: "Workflow") var workflow: WorkflowEntity

    init() {}
    init(workflow: WorkflowEntity) { self.workflow = workflow }

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$workflow)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = workflow.id
        let line = await WorkflowRequests.handle?(id) ?? WorkflowRequests.unavailable
        return .result(dialog: "\(line)")
    }
}

/// Runs what Mantiza suggests for this time of day: the Control Center button.
struct RunSuggestedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Run Mantiza's Suggestion"
    static let description = IntentDescription("Runs the workflow Mantiza suggests right now.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = await WorkflowRequests.handle?(nil) ?? WorkflowRequests.unavailable
        return .result(dialog: "\(line)")
    }
}
