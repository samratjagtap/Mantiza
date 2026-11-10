import MantizaKit
import SwiftUI
import WidgetKit

// Mantiza's widget: one-tap tasks (your recent ones first) and the last result, in Mantiza's pixel
// style. Tapping a task opens Mantiza and runs it (mantiza://run?q=...); the app does the work,
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

    // Small: the head, the last result, tap to open Mantiza.
    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelArt(Logo.head, animated: false, assemble: false).frame(height: 46)
            Spacer(minLength: 0)
            if let last = entry.last {
                LastLine(last: last, lines: 3)
            } else {
                Text("tap to ask").font(Theme.mono(12)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(Shared.newURL)
    }

    // Medium: head + wordmark on the left, three tasks on the right.
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                PixelArt(Logo.head, animated: false, assemble: false).frame(height: 44)
                PixelArt(Logo.wordmark, animated: false, assemble: false).frame(height: 9)
                Spacer(minLength: 0)
                Link(destination: Shared.newURL) {
                    Text("> ASK").font(Theme.mono(11, .bold)).tracking(1.5).foregroundStyle(Theme.green)
                }
            }
            .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.tasks.prefix(3), id: \.self) { TaskButton(task: $0) }
                Spacer(minLength: 0)
            }
        }
    }

    // Large: wordmark, last result, six tasks.
    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PixelArt(Logo.wordmark, animated: false, assemble: false).frame(height: 12)
                Spacer()
                PixelArt(Logo.small, animated: false, assemble: false).frame(height: 22)
            }
            if let last = entry.last {
                LastLine(last: last, lines: 2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
            }
            ForEach(entry.tasks.prefix(6), id: \.self) { TaskButton(task: $0) }
            Spacer(minLength: 0)
            Link(destination: Shared.newURL) {
                Text("> ASK SOMETHING NEW").font(Theme.mono(11, .bold)).tracking(1.5).foregroundStyle(Theme.green)
            }
        }
    }
}

/// One task as a sharp, tappable row.
struct TaskButton: View {
    let task: String
    var body: some View {
        Link(destination: Shared.runURL(task)) {
            HStack(spacing: 7) {
                Rectangle().fill(Theme.magenta).frame(width: 5, height: 5)
                Text(task).font(Theme.mono(11)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.panel)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
        }
    }
}

/// "■ Turn on the flashlight · 5 min ago"
struct LastLine: View {
    let last: Shared.LastTask
    let lines: Int
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Rectangle().fill(last.ok ? Theme.green : Theme.magenta).frame(width: 6, height: 6).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(last.prompt).font(Theme.mono(11, .semibold)).foregroundStyle(Theme.text).lineLimit(lines)
                Text(last.when, style: .relative).font(Theme.mono(9)).foregroundStyle(Theme.dim)
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
                PixelArt(Logo.small, animated: false, assemble: false).padding(9)
            }
            .widgetURL(Shared.newURL)
        default:
            HStack(spacing: 8) {
                PixelArt(Logo.small, animated: false, assemble: false).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MANTIZA").font(Theme.mono(11, .bold)).tracking(2)
                    Text(entry.last?.prompt ?? "tap to ask").font(Theme.mono(10)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(Shared.newURL)
        }
    }
}
