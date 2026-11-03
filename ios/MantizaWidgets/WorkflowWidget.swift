import AppIntents
import SwiftUI
import WidgetKit

struct WorkflowEntry: TimelineEntry {
    let date: Date
    let tab: WidgetSnapshot.Tab
    let items: [WidgetSnapshot.Item]
}

struct WorkflowProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkflowEntry {
        WorkflowEntry(date: .now, tab: .now, items: [.init(id: "x", name: "Reply to Azad", app: "Messages")])
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkflowEntry) -> Void) { completion(entry()) }

    /// Suggestions change with the time of day, so refresh hourly (the app also reloads after each run).
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkflowEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entry() -> WorkflowEntry {
        let snap = WidgetSnapshot.load(), tab = WidgetSnapshot.selectedTab
        return WorkflowEntry(date: .now, tab: tab, items: snap.tabs[tab] ?? [])
    }
}

struct WorkflowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "workflows", provider: WorkflowProvider()) { entry in
            WorkflowWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mantiza workflows")
        .description("Run the workflows you use at this time of day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

struct WorkflowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WorkflowEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let first = entry.items.first {
                Link(destination: WidgetSnapshot.runURL(first.id)) { Image(systemName: "hand.tap") }
            } else {
                Image(systemName: "hand.tap")
            }
        case .accessoryRectangular:
            if let first = entry.items.first {
                Link(destination: WidgetSnapshot.runURL(first.id)) {
                    VStack(alignment: .leading) {
                        Text("Mantiza").font(.caption2.bold())
                        Text(first.name).font(.caption).lineLimit(2)
                    }
                }
            } else {
                Text("Mantiza: no suggestions yet").font(.caption)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Label("Mantiza", systemImage: "hand.tap").font(.caption.bold())
                if let first = entry.items.first {
                    Link(destination: WidgetSnapshot.runURL(first.id)) { row(first) }
                } else {
                    Text("Save a workflow to see it here.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(WidgetSnapshot.Tab.allCases, id: \.self) { tab in
                        Button(intent: SelectWidgetTabIntent(tab: tab)) {
                            Text(tab.title).font(.caption.bold())
                                .foregroundStyle(tab == entry.tab ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Image(systemName: "hand.tap").foregroundStyle(.secondary)
                }
                if entry.items.isEmpty {
                    Text("Nothing here yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entry.items.prefix(family == .systemLarge ? 6 : 3)) { item in
                    Link(destination: WidgetSnapshot.runURL(item.id)) { row(item) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.callout).lineLimit(1)
                if let app = item.app { Text(app).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").foregroundStyle(.tint)
        }
    }
}
