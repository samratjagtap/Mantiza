import MantizaKit
import SwiftUI
import WidgetKit

// Mantiza's widget: one-tap tasks (your recent ones first) and the last result, in the app's calm
// style (dark, soft rows, system type, the pixel head). Tapping a task opens Mantiza and runs it (mantiza://run?q=...); the app does the work,
// because tasks need the screen and the device.

@main
struct MantizaWidgets: WidgetBundle {
    var body: some Widget {
        QuickTasksWidget()
        LockWidget()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let tasks: [String]
    let last: Shared.LastTask?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, tasks: Shared.starters, last: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget after every task; refresh hourly so "x min ago" stays fresh.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entry() -> Entry {
        Entry(date: .now, tasks: Shared.quickTasks(6), last: Shared.last)
    }
}

// MARK: - Home Screen widget

struct QuickTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MantizaQuickTasks", provider: Provider()) { entry in
            QuickTasksView(entry: entry)
                .containerBackground(Theme.ink, for: .widget)
        }
        .configurationDisplayName("Mantiza")
        .description("Your tasks, one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickTasksView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    // Small: the head, the last task, tap to open Mantiza.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelArt(Logo.head, animated: false).frame(height: 34)
            Spacer(minLength: 8)
            if let last = entry.last {
                LastLine(last: last, lines: 3)
            } else {
                Text("Ask Mantiza").font(Theme.sans(14, .medium)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(Shared.newURL)
    }

    // Medium: head and ask button on the left, three tasks on the right.
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                PixelArt(Logo.head, animated: false).frame(height: 34)
                Spacer(minLength: 0)
                AskButton()
            }
            .frame(width: 84, alignment: .leading)
            VStack(spacing: 6) {
                ForEach(entry.tasks.prefix(3), id: \.self) { TaskButton(task: $0) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // Large: head, last task, five tasks, ask button.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                PixelArt(Logo.head, animated: false).frame(height: 30)
                Spacer()
                AskButton()
            }
            if let last = entry.last {
                LastLine(last: last, lines: 2)
            }
            VStack(spacing: 6) {
                ForEach(entry.tasks.prefix(5), id: \.self) { TaskButton(task: $0) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The round magenta "Ask" button (opens Mantiza on the Task screen).
struct AskButton: View {
    var body: some View {
        Link(destination: Shared.newURL) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                Text("Ask").font(Theme.sans(13, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.magenta))
        }
    }
}

/// One task as a soft, tappable row.
struct TaskButton: View {
    let task: String
    var body: some View {
        Link(destination: Shared.runURL(task)) {
            Text(task).font(Theme.sans(13)).foregroundStyle(Theme.text).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// "● Turn on the flashlight · 5 min ago"
struct LastLine: View {
    let last: Shared.LastTask
    let lines: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(last.ok ? Theme.green : Theme.magenta).frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(last.prompt).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text).lineLimit(lines)
                Text(last.when, style: .relative).font(Theme.sans(11)).foregroundStyle(Theme.dim)
            }
        }
    }
}

// MARK: - Lock Screen

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MantizaLock", provider: Provider()) { entry in
            LockView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Mantiza")
        .description("Open Mantiza from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                PixelArt(Logo.small, animated: false).padding(10)
            }
            .widgetURL(Shared.newURL)
        default:
            HStack(spacing: 8) {
                PixelArt(Logo.small, animated: false).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mantiza").font(Theme.sans(13, .semibold))
                    Text(entry.last?.prompt ?? "Ask Mantiza").font(Theme.sans(12)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(Shared.newURL)
        }
    }
}
