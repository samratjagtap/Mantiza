import SwiftUI

/// Saved workflows: suggested now, pinned, all; run, pin or delete. Run history is one tap away.
struct WorkflowsView: View {
    @Environment(AppModel.self) private var app
    @State private var refresh = 0

    var body: some View {
        let store = app.workflows
        let suggested = store.suggestions()
        List {
            if store.workflows.isEmpty {
                Text("After a task works, tap “Save as a workflow” on the Run tab. Saved workflows run again with fewer AI calls and show up on the stick at the times you use them.")
                    .foregroundStyle(.secondary)
            }
            if !suggested.isEmpty {
                Section("Suggested now") { ForEach(suggested) { row($0) } }
            }
            if !store.workflows.isEmpty {
                Section("All") {
                    ForEach(store.workflows) { row($0) }
                        .onDelete { idx in idx.map { store.workflows[$0] }.forEach(store.delete); refresh += 1 }
                }
            }
            Section { NavigationLink("Run history") { RunsView() } }
        }
        .id(refresh)
        .navigationTitle("Workflows")
    }

    private func row(_ w: Workflow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).lineLimit(1)
                Text("\(w.subtask.app ?? "Any app") · \(w.steps.count) steps · used \(w.uses.count)×")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                var copy = w
                copy.pinned.toggle()
                app.workflows.update(copy)
                app.publishWidget()
                refresh += 1
            } label: { Image(systemName: w.pinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain)
            Button("Run") { Task { await app.run(w) } }
                .buttonStyle(.borderedProminent)
                .disabled(!app.inputReady || app.runner.running)
        }
    }
}
