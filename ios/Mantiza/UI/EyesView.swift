import SwiftUI

/// Debug screen for the eyes: share the screen, read its text, tap an element through the stick.
/// The M3 check: start sharing, open Settings, come back, and "tap General" opens General.
struct EyesView: View {
    @Environment(AppModel.self) private var app
    @State private var reading: ScreenReading?
    @State private var frame: Frame?
    @State private var message = ""
    @State private var query = "General"
    @State private var appName = "Settings"
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Button(app.screen.live ? "Stop sharing" : "Share screen") {
                    act {
                        if app.screen.live { await app.screen.stop() } else {
                            if let still = app.screen as? StillScreen { still.show(DemoScreen.settings()) }
                            try await app.screen.start()
                        }
                    }
                }
                Button("Read the screen") { act { try await read() } }.disabled(!app.screen.live)
            } footer: {
                Text("After sharing starts, go to another app and back. Reading happens on this iPhone.")
            }
            Section("Tap by text") {
                TextField("App", text: $appName).autocorrectionDisabled()
                TextField("Text on screen", text: $query).autocorrectionDisabled()
                Button("Open \(appName), then tap “\(query)”") {
                    act { try await tapFromHome() }
                }
                .disabled(!app.screen.live || !app.inputReady || query.isEmpty)
            }
            if !message.isEmpty { Section { Text(message).font(.footnote) } }
            if let frame {
                Section("Last frame #\(frame.id)") {
                    Image(decorative: frame.image, scale: 1).resizable().scaledToFit().frame(maxHeight: 320)
                }
            }
            if let reading {
                Section("\(reading.elements.count) text elements") {
                    ForEach(reading.elements) { e in
                        Button {
                            act { try await tap(e) }
                        } label: {
                            HStack {
                                Text("\(e.id)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                Text(e.text)
                                Spacer()
                                Text("\(Int(e.center.x * 1000)),\(Int(e.center.y * 1000))").font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!app.inputReady)
                    }
                }
            }
        }
        .navigationTitle("Look")
        .disabled(busy)
    }

    private func read() async throws {
        guard let f = app.screen.latest else { throw ScreenError.notSharing }
        let started = Date()
        let r = try await OCR.read(f)
        frame = f
        reading = r
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        message = "Read \(r.elements.count) elements in \(ms) ms."
        Log.event("eyes.read", ["frame": f.id, "elements": r.elements.count, "ms": ms])
    }

    private func tap(_ e: ScreenElement) async throws {
        try await app.hands.tap(e.center)
        message = "Tapped \(e.text)."
    }

    /// Leave Mantiza, open the app through Spotlight, read it, tap the element whose text matches.
    private func tapFromHome() async throws {
        try await AppLauncher.open(appName, hands: app.hands, screen: app.screen, openURL: { url in
            await UIApplication.shared.open(url)
        })
        let f = try await app.screen.settled(after: Date().addingTimeInterval(-0.2), quiet: 0.4, most: 3)
        let r = try await OCR.read(f)
        frame = f
        reading = r
        guard let target = r.find(query).first else {
            message = "“\(query)” is not on screen. Seen: \(r.elements.prefix(8).map(\.text).joined(separator: ", "))"
            Log.event("eyes.tap", ["query": query, "found": false, "seen": r.elements.prefix(12).map(\.text)])
            return
        }
        let before = Date()
        try await app.hands.tap(target.center)
        let after = try await app.screen.settled(after: before)
        let changed = ScreenDiff.changed(f.image, after.image)
        message = "Tapped “\(target.text)”; screen \(changed ? "changed" : "did not change")."
        Log.event("eyes.tap", ["query": query, "found": true, "changed": changed])
    }

    private func act(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await work() } catch {
                message = error.localizedDescription
                Log.event("eyes.error", ["message": message])
            }
            busy = false
        }
    }
}
