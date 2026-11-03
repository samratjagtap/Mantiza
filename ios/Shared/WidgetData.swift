import AppIntents
import Foundation
import WidgetKit

/// What the widget shows, written by the app into the App Group container.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String  // workflow id
        var name: String
        var app: String?
    }

    enum Tab: String, Codable, CaseIterable, AppEnum {
        case now, pinned, recent
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tab"
        static let caseDisplayRepresentations: [Tab: DisplayRepresentation] = [
            .now: "Now", .pinned: "Pinned", .recent: "Recent",
        ]
        var title: String { rawValue.capitalized }
    }

    var tabs: [Tab: [Item]] = [:]
    /// Every saved workflow (Siri and Shortcuts list these).
    var all: [Item] = []
    var updated = Date()

    static let group = "group." + (Bundle.main.bundleIdentifier ?? "com.azadjagtap.mantiza")
        .replacingOccurrences(of: ".widgets", with: "")

    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: "snapshot"),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Self.defaults?.set(data, forKey: "snapshot") }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var selectedTab: Tab {
        get { Tab(rawValue: defaults?.string(forKey: "tab") ?? "") ?? .now }
        set { defaults?.set(newValue.rawValue, forKey: "tab") }
    }

    static func runURL(_ id: String) -> URL { URL(string: "mantiza://run/\(id)")! }
}

/// Switches the widget's tab without opening the app.
struct SelectWidgetTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Show workflows"
    @Parameter(title: "Tab") var tab: WidgetSnapshot.Tab

    init() {}
    init(tab: WidgetSnapshot.Tab) { self.tab = tab }

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.selectedTab = tab
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
