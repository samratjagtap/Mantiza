import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MantizaWidgets: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
        AgentCanvasWidget()
        WorkflowWidget()
        RunSuggestionControl()
    }
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunAttributes.self) { context in
            LockScreenRun(goal: context.attributes.goal, runID: context.attributes.runID, state: context.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Mantiza", systemImage: "hand.tap").font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.total > 0 { Text("\(s.step)/\(s.total)").font(.caption.monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.result ?? s.question ?? s.action).font(.callout).lineLimit(2)
                        RunButtons(state: s, runID: context.attributes.runID)
                    }
                }
            } compactLeading: {
                Image(systemName: s.question != nil ? "exclamationmark.bubble" : "hand.tap")
            } compactTrailing: {
                Text(s.total > 0 ? "\(s.step)/\(s.total)" : "…").font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: s.question != nil ? "exclamationmark.bubble" : "hand.tap")
            }
        }
    }
}

struct LockScreenRun: View {
    let goal: String
    let runID: String
    let state: RunAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(goal, systemImage: "hand.tap").font(.headline).lineLimit(1)
                Spacer()
                if state.total > 0 && state.result == nil {
                    Text("\(state.step)/\(state.total)").font(.caption.monospacedDigit())
                }
            }
            if state.total > 0 && state.result == nil {
                ProgressView(value: Double(min(state.step, state.total)), total: Double(state.total))
            }
            Text(state.result ?? state.question ?? state.action).font(.callout).lineLimit(2)
            RunButtons(state: state, runID: runID)
        }
        .foregroundStyle(.white)
    }
}

struct RunButtons: View {
    let state: RunAttributes.ContentState
    let runID: String

    var body: some View {
        if state.result != nil {
            EmptyView()
        } else if state.question != nil {
            HStack {
                Button(intent: AnswerApprovalIntent(approve: false)) { Text("Cancel") }.tint(.gray)
                Button(intent: AnswerApprovalIntent(approve: true)) { Text("Approve") }.tint(.green)
            }
        } else {
            HStack {
                Button(intent: PauseRunIntent(runID: runID)) {
                    Label(state.paused ? "Resume" : "Pause", systemImage: state.paused ? "play.fill" : "pause.fill")
                }
                .tint(.blue)
                Button(intent: StopRunIntent(runID: runID)) { Label("Stop", systemImage: "stop.fill") }.tint(.red)
            }
        }
    }
}
