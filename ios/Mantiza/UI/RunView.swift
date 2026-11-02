import SwiftUI

/// Ask Mantiza for something and watch it work.
struct RunView: View {
    @Environment(AppModel.self) private var app
    @State private var request = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        let runner = app.runner
        List {
            Section {
                TextField("What should Mantiza do?", text: $request, axis: .vertical)
                    .lineLimit(1...4)
                if runner.running {
                    Button("Stop", role: .destructive) { app.requestStop(); task?.cancel() }
                } else {
                    Button("Run") { start() }
                        .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || !app.inputReady)
                }
            } footer: {
                if !app.inputReady {
                    Text("Connect Mantiza Hands and pair its pointer on the Device tab first.")
                } else {
                    Text("Mantiza asks you to share the screen, then works in the other app. Press B on the stick or shake it to stop. It asks on the stick before sending, deleting or buying.")
                }
            }
            if !runner.status.isEmpty {
                Section("Status") { Text(runner.status) }
            }
            if let s = runner.subtask {
                Section("Plan") {
                    Text(s.goal)
                    if let a = s.app { LabeledContent("App", value: a) }
                    ForEach(s.verification, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                }
            }
            if !runner.steps.isEmpty {
                Section("Steps") {
                    ForEach(runner.steps) { step in
                        HStack(alignment: .top) {
                            Text("\(step.id)").monospacedDigit().foregroundStyle(.secondary)
                            Text(step.text)
                            Spacer()
                            if step.ms > 0 { Text("\(step.ms) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Run")
    }

    private func start() {
        let text = request
        task = Task { await app.run(text) }
    }
}
