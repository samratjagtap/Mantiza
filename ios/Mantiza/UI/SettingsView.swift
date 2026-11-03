import SwiftUI

/// AI providers, models and keys; recent log lines.
struct SettingsView: View {
    @State private var big = AISettings.big
    @State private var claudeModel = AISettings.claudeModel
    @State private var geminiModel = AISettings.geminiModel
    @State private var fast = AISettings.fast
    @State private var layaURL = AISettings.layaURL

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
                Picker("Quick steps", selection: $fast) {
                    Text("Laya (your server)").tag(AISettings.Fast.laya)
                    Text("Jev (TypeSafe)").tag(AISettings.Fast.jev)
                    Text("Off").tag(AISettings.Fast.off)
                }
                if fast == .laya {
                    TextField("http://10.0.0.243:8765", text: $layaURL)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            } header: {
                Text("Quick steps")
            } footer: {
                Text(fast == .laya
                     ? "Laya runs on your Mac (tools/laya/serve.sh prints the address and key). It picks taps from the text on screen; unsure steps go to the big brain."
                     : "The quick picker chooses most taps from the text on screen in a fraction of a second; unsure steps go to the big brain.")
            }
            Section("Keys") { KeysForm() }
            Section {
                NavigationLink("Safety") { SafetyView() }
                NavigationLink("Privacy") { PrivacyView() }
            }
            Section("Log") {
                NavigationLink("Recent events") { LogView() }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: big) { _, v in AISettings.big = v }
        .onChange(of: claudeModel) { _, v in AISettings.claudeModel = v }
        .onChange(of: geminiModel) { _, v in AISettings.geminiModel = v }
        .onChange(of: fast) { _, v in AISettings.fast = v }
        .onChange(of: layaURL) { _, v in AISettings.layaURL = v }
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
