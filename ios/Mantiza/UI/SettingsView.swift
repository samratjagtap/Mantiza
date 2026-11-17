import SwiftUI

/// AI providers, models and keys; recent log lines.
struct SettingsView: View {
    @State private var big = AISettings.big
    @State private var claudeModel = AISettings.claudeModel
    @State private var geminiModel = AISettings.geminiModel
    @State private var fast = AISettings.fast
    @State private var layaURL = AISettings.layaURL
    @State private var useMap = AISettings.useMap
    @State private var mapScreens: Int?
    @Environment(AppModel.self) private var app

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
                    TextField("http://your-mac.local:8765", text: $layaURL)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if Reachability.isDown("laya") {
                        Label("Not reachable on this Wi-Fi. Steps use the big brain.", systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Quick steps")
            } footer: {
                Text(fast == .laya
                     ? "Laya runs on your Mac (tools/laya/serve.sh prints the address and key; Mantiza finds the Mac on the same Wi-Fi by itself). It picks taps from the text on screen; unsure steps go to the big brain."
                     : "The quick picker chooses most taps from the text on screen in a fraction of a second; unsure steps go to the big brain.")
            }
            Section {
                Toggle("Learn and use the phone map", isOn: $useMap)
                LabeledContent("Screens learned", value: "\(mapScreens ?? app.map.map.screens.count)")
                Button("Forget the map", role: .destructive) { app.map.deleteAll(); mapScreens = 0 }
                    .disabled((mapScreens ?? app.map.map.screens.count) == 0)
            } header: {
                Text("Phone map")
            } footer: {
                Text("Each task teaches Mantiza which screen is which and which tap leads where. Later tasks walk known paths with no AI calls and check every screen they land on; when the phone has changed, the AI takes over from there and the map learns the new way.")
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
        .onChange(of: useMap) { _, v in AISettings.useMap = v }
        .onChange(of: layaURL) { _, v in AISettings.layaURL = v; Reachability.reset("laya") }
    }
}

struct LogView: View {
    @State private var lines = Log.recent

    var body: some View {
        List {
            let reports = CrashReports.files
            if !reports.isEmpty {
                Section("Crash and hang reports from iOS") {
                    ForEach(reports, id: \.self) { url in ShareLink(url.lastPathComponent, item: url) }
                }
            }
            Section("Recent events") {
                ForEach(lines.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
            .navigationTitle("Log")
            .refreshable { lines = Log.recent }
    }
}
