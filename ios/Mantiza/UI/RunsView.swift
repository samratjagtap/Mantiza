import SwiftUI

/// Past runs with their steps and timings; each can be shared as JSON.
struct RunsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if app.runs.runs.isEmpty { Text("No runs yet.").foregroundStyle(.secondary) }
            ForEach(app.runs.runs) { r in
                NavigationLink {
                    RunDetailView(run: r)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(r.success ? .green : .orange)
                            Text(r.request).lineLimit(1)
                        }
                        Text("\(r.date.formatted(date: .abbreviated, time: .shortened)) · \(r.steps.count) steps · \(Double(r.totalMs) / 1000, specifier: "%.1f") s")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in idx.map { app.runs.runs[$0] }.forEach(app.runs.delete) }
        }
        .navigationTitle("Runs")
    }
}

struct RunDetailView: View {
    @Environment(AppModel.self) private var app
    let run: RunRecord

    var body: some View {
        List {
            Section {
                Text(run.outcome)
                LabeledContent("Big brain", value: run.bigBrain)
                LabeledContent("AI calls", value: "\(run.bigCalls) big, \(run.fastCalls) quick")
                LabeledContent("Total", value: String(format: "%.1f s", Double(run.totalMs) / 1000))
            }
            Section("Steps (decide / see / read / act, ms)") {
                ForEach(run.steps) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.text)
                        Text("\(s.ms) / \(s.captureMs) / \(s.ocrMs) / \(s.actMs)").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(run.request)
        .toolbar { ShareLink(item: app.runs.url(run)) }
    }
}
