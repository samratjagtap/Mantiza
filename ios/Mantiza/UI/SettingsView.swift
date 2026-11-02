import SwiftUI

/// AI providers, models and keys; recent log lines.
struct SettingsView: View {
    @State private var big = AISettings.big
    @State private var claudeModel = AISettings.claudeModel
    @State private var geminiModel = AISettings.geminiModel
    @State private var useJev = AISettings.useJev

    var body: some View {
        Form {
            Section("Big brain") {
                Picker("Provider", selection: $big) {
                    Text("Claude").tag(AISettings.Big.claude)
                    Text("Gemini").tag(AISettings.Big.gemini)
                }
                if big == .claude {
                    Picker("Model", selection: $claudeModel) {
                        ForEach(ClaudeBrain.models, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Gemini model", text: $geminiModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            Section {
                Toggle("Use Jev for quick steps", isOn: $useJev)
            } footer: {
                Text("Jev picks most taps from the text on screen in a fraction of a second; unsure steps go to the big brain.")
            }
            Section("Keys") { KeysForm() }
            Section("Log") {
                NavigationLink("Recent events") { LogView() }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: big) { _, v in AISettings.big = v }
        .onChange(of: claudeModel) { _, v in AISettings.claudeModel = v }
        .onChange(of: geminiModel) { _, v in AISettings.geminiModel = v }
        .onChange(of: useJev) { _, v in AISettings.useJev = v }
    }
}

struct LogView: View {
    @State private var lines = Log.recent

    var body: some View {
        List(lines.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
            .navigationTitle("Log")
            .refreshable { lines = Log.recent }
    }
}
