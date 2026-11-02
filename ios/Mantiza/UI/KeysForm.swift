import SwiftUI

/// Paste the AI service keys; they go straight to the Keychain.
struct KeysForm: View {
    @State private var drafts: [KeyStore.Provider: String] = [:]
    @State private var saved: Set<KeyStore.Provider> = Set(KeyStore.Provider.allCases.filter { KeyStore.get($0) != nil })

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste your API keys. They stay in this iPhone's Keychain and go only to that company. Claude is needed; Jev makes most steps faster; Gemini is optional.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(KeyStore.Provider.allCases) { p in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(p.title).font(.headline)
                        Spacer()
                        if saved.contains(p) { Label("Saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                    }
                    HStack {
                        SecureField(saved.contains(p) ? "Replace key" : "Key", text: binding(p))
                            .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeyStore.set(p, drafts[p])
                            drafts[p] = ""
                            saved = Set(KeyStore.Provider.allCases.filter { KeyStore.get($0) != nil })
                        }
                        .disabled((drafts[p] ?? "").isEmpty)
                        if saved.contains(p) {
                            Button(role: .destructive) {
                                KeyStore.set(p, nil)
                                saved.remove(p)
                            } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
        }
    }

    private func binding(_ p: KeyStore.Provider) -> Binding<String> {
        Binding(get: { drafts[p] ?? "" }, set: { drafts[p] = $0 })
    }
}
