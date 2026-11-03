import SwiftUI

/// Ask Mantiza for something and watch it work.
struct RunView: View {
    @Environment(AppModel.self) private var app
    @State private var request = ""
    @State private var task: Task<Void, Never>?
    @State private var voice = VoiceInput()
    @State private var savedID: UUID?

    var body: some View {
        let runner = app.runner
        List {
            Section {
                if app.sessionLive {
                    Label("Session on. Hold A on the stick and talk.", systemImage: "waveform")
                    Button("End session", role: .destructive) { Task { await app.stopSession() } }
                } else {
                    Button { Task { await app.startSession() } } label: {
                        Label("Start session", systemImage: "play.circle.fill")
                    }
                    .disabled(!app.inputReady)
                }
                if app.talk.transcribing { Label("Listening to the stick…", systemImage: "ear") }
                else if !app.talk.lastHeard.isEmpty { LabeledContent("Heard", value: app.talk.lastHeard) }
            } header: {
                Text("Talk to the stick")
            } footer: {
                Text("Start once: Mantiza shares the screen, then hold A on the stick from anywhere and say what to do. The session ends when the iPhone locks or you end it.")
            }
            Section {
                HStack(alignment: .top) {
                    TextField("What should Mantiza do?", text: $request, axis: .vertical)
                        .lineLimit(1...4)
                    Button {
                        Task {
                            if voice.listening { request = await voice.stop() } else { await voice.start() }
                        }
                    } label: {
                        Image(systemName: voice.listening ? "stop.circle.fill" : "mic.circle")
                            .font(.title2)
                            .foregroundStyle(voice.listening ? .red : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(voice.listening ? "Stop listening" : "Speak your request")
                }
                if voice.listening { Text(voice.text.isEmpty ? "Listening…" : voice.text).foregroundStyle(.secondary) }
                if !voice.error.isEmpty { Text(voice.error).font(.footnote).foregroundStyle(.red) }
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
                Section("Status") {
                    Text(runner.status)
                    if !runner.running, let r = app.lastRecord, r.success, r.workflowID == nil {
                        if savedID == r.id {
                            Label("Saved to Workflows", systemImage: "checkmark").foregroundStyle(.green)
                        } else {
                            Button("Save as a workflow") { if app.saveLastAsWorkflow() != nil { savedID = r.id } }
                        }
                    }
                }
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
