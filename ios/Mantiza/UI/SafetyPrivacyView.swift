import SwiftUI

/// What Mantiza refuses to do, and what it asked you before doing.
struct SafetyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                Text("Mantiza hides these buttons from the AI unless your request asks for that kind of action, and then asks you on the stick (A = yes, B = no) or on the phone before each one.")
                    .font(.callout)
                ForEach(Safety.riskWords.keys.sorted(), id: \.self) { kind in
                    LabeledContent(kind.capitalized, value: Safety.riskWords[kind]!.prefix(5).joined(separator: ", "))
                }
            } header: { Text("Asks first") }
            Section {
                Text("Mantiza stops on screens with these words and never types PINs, one-time codes or card numbers.")
                    .font(.callout)
                Text(Safety.stopPhrases.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Never") }
            Section("Your answers") {
                if app.approvals.history.isEmpty { Text("No approvals yet.").foregroundStyle(.secondary) }
                ForEach(app.approvals.history) { e in
                    HStack {
                        Image(systemName: e.approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(e.approved ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(e.question)
                            Text("\(e.date.formatted(date: .abbreviated, time: .shortened)) · \(e.source)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Safety")
    }
}

/// What is stored where, who receives data, and deleting it all.
struct PrivacyView: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false
    @State private var deleted = false

    var body: some View {
        List {
            Section("Sent to AI services during a task") {
                LabeledContent("Anthropic (Claude)", value: "screenshots, screen text")
                LabeledContent("Google (Gemini)", value: "screenshots, screen text")
                LabeledContent("Laya (your own server)", value: "screen text")
                LabeledContent("TypeSafe (Jev), if chosen", value: "screen text")
                Text("Only the service you choose as big brain receives screenshots. The quick picker never receives images.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Kept on this iPhone") {
                LabeledContent("Runs", value: "\(app.runs.runs.count)")
                LabeledContent("Workflows", value: "\(app.workflows.workflows.count)")
                LabeledContent("Approvals", value: "\(app.approvals.history.count)")
                LabeledContent("API keys", value: "Keychain")
                Text("Screen images are not saved. Runs keep each step's text and timing; training examples keep the text read from each screen, so Laya on your Mac can learn from Claude's choices.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Delete all data", role: .destructive) { confirm = true }
                if deleted { Label("Deleted", systemImage: "checkmark").foregroundStyle(.green) }
            } footer: {
                Text("Removes runs, training examples, workflows, approvals, calibration and API keys from this iPhone.")
            }
        }
        .navigationTitle("Privacy")
        .confirmationDialog("Delete all Mantiza data on this iPhone?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                app.deleteAllData()
                deleted = true
            }
        }
    }
}
