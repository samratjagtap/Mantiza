import ActivityKit
import AppIntents
import MantizaKit
import SwiftUI
import WidgetKit

// Mantiza's widget: one-tap tasks (your recent ones first) and the last result, in the app's calm
// style (dark, soft rows, system type, the pixel head). Tapping a task opens Mantiza and runs it (mantiza://run?q=...); the app does the work,
// because tasks need the screen and the device.

/// The Control Centre button only exists when iOS can run its action (the App Intents index is
/// packed): a control that does nothing when pressed is worse than none. A widget bundle can't hold
/// an "if", so there are two bundles and the start picks one.
@main
enum MantizaWidgetsMain {
    static func main() {
        if Shared.actionsIndexed { WidgetsWithControl.main() } else { MantizaWidgets.main() }
    }
}

struct MantizaWidgets: WidgetBundle {
    var body: some Widget {
        QuickTasksWidget()
        LockWidget()
        TaskLiveActivity()
    }
}

struct WidgetsWithControl: WidgetBundle {
    var body: some Widget {
        QuickTasksWidget()
        LockWidget()
        TaskLiveActivity()
        TalkControl()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let tasks: [Shared.Suggestion]
    let last: Shared.LastTask?
    var relevance: TimelineEntryRelevance?
}

/// The widget changes through the day by itself: the timeline holds one entry per half hour for
/// the next 8 hours, each with the tasks you usually ask around that time (Shared.suggestions).
/// iOS swaps the entries in without waking the app. Entries with a habit get a higher relevance,
/// so a Smart Stack turns to Mantiza when it has something for that moment.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, tasks: Shared.starters.map { Shared.Suggestion(prompt: $0, habit: false) }, last: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry(at: .now, runs: Shared.history))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let runs = Shared.history
        let now = Date()
        let half: TimeInterval = 1800
        let next = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / half).rounded(.up) * half)
        var entries = [entry(at: now, runs: runs)]
        for i in 0..<16 { entries.append(entry(at: next.addingTimeInterval(Double(i) * half), runs: runs)) }
        // The app also reloads the widget after every task.
        completion(Timeline(entries: entries, policy: .after(next.addingTimeInterval(15 * half))))
    }

    private func entry(at date: Date, runs: [Shared.Run]) -> Entry {
        let tasks = Shared.suggestions(at: date, count: 6, from: runs)
        return Entry(date: date, tasks: tasks, last: Shared.last,
                     relevance: TimelineEntryRelevance(score: tasks.contains { $0.habit } ? 80 : 20))
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

/// One task as a soft, tappable row: a tap opens Mantiza and runs it. A small clock marks a task
/// you usually ask around this time.
struct TaskButton: View {
    let task: Shared.Suggestion
    var body: some View {
        Link(destination: Shared.runURL(task.prompt)) {
            HStack(spacing: 6) {
                if task.habit { Image(systemName: "clock").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.green) }
                Text(task.prompt).font(Theme.sans(13)).foregroundStyle(Theme.text).lineLimit(1)
            }
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
        .description("Talk to Mantiza from the Lock Screen.")
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
            .widgetURL(Shared.listenURL)  // one tap from the Lock Screen: Mantiza opens listening
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

// MARK: - Live Activity: the running task on the Lock Screen and in the Dynamic Island

struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivity.self) { context in
            LiveTaskView(request: context.attributes.request, state: context.state, stale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Theme.ink)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PixelArt(Logo.small, animated: false).frame(width: 30, height: 30)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .working || context.state.phase == .asking { StopButton() }
                    else { PhaseMark(phase: context.state.phase) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.request).font(Theme.sans(13)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status).font(Theme.sans(15, .medium)).foregroundStyle(.white)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                PixelArt(Logo.small, animated: false).frame(width: 18, height: 18)
            } compactTrailing: {
                PhaseMark(phase: context.state.phase)
            } minimal: {
                PhaseMark(phase: context.state.phase)
            }
            .widgetURL(Shared.newURL)
        }
    }
}

/// Lock Screen and banner: the head, what was asked, what is happening now, and Stop.
struct LiveTaskView: View {
    let request: String
    let state: TaskActivity.ContentState
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PixelArt(Logo.head, animated: false).frame(width: 40, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(request).font(Theme.sans(12)).foregroundStyle(Theme.dim).lineLimit(1)
                Text(stale ? "No update for a while: open Mantiza to check" : state.status)
                    .font(Theme.sans(15, .medium))
                    .foregroundStyle(state.phase == .failed ? Theme.magenta : Theme.text)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if (state.phase == .working || state.phase == .asking) && !stale { StopButton() }
            else { PhaseMark(phase: state.phase) }
        }
    }
}

/// Stop, without opening Mantiza where iOS can run the action (the App Intents index is packed);
/// otherwise a link that opens Mantiza and stops.
struct StopButton: View {
    var body: some View {
        if Shared.actionsIndexed {
            Button(intent: StopTaskIntent()) { label }.buttonStyle(.plain)
        } else {
            Link(destination: Shared.stopURL) { label }
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
            Text("Stop").font(Theme.sans(13, .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.text))
    }
}

/// A small mark for the task's state: working, waiting for you, done, failed, stopped.
struct PhaseMark: View {
    let phase: TaskActivity.Phase
    var body: some View {
        switch phase {
        case .working: Image(systemName: "ellipsis").foregroundStyle(Theme.text)
        case .asking: Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.magenta)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.magenta)
        case .stopped: Image(systemName: "stop.circle.fill").foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - Control: a button for Control Centre, the Lock Screen and the Action Button

/// "Talk to Mantiza": opens Mantiza already listening. It shows up under Controls only when the
/// App Intents index is packed (scripts/make_intents.py).
struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MantizaTalk") {
            ControlWidgetButton(action: ListenIntent()) {
                Label("Talk to Mantiza", systemImage: "mic.fill")
            }
        }
        .displayName("Talk to Mantiza")
        .description("Opens Mantiza ready to listen.")
    }
}
