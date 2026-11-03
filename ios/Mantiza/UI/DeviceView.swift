import Accessibility
import SwiftUI

/// The stick: connection, pointer state, battery, calibration, and test gestures.
struct DeviceView: View {
    @Environment(AppModel.self) private var app
    @State private var calibrating = false
    @State private var testResult = ""
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                LabeledContent("Stick", value: app.boardConnected ? app.boardName : "Not connected")
                LabeledContent("Pointer and keyboard", value: app.inputReady ? "Ready" : "Not paired")
                if let s = app.boardStatus {
                    if let b = s.battery { LabeledContent("Battery", value: "\(b)%" + (s.chg == true ? " charging" : "")) }
                    if let fw = s.fw { LabeledContent("Firmware", value: fw) }
                    if let drops = s.ble?.hdrop, drops > 0 { LabeledContent("Dropped input reports", value: "\(drops)") }
                }
                if let code = app.link.pairingCode {
                    PairingCodeView(code: code)
                }
                if !app.link.lastError.isEmpty && app.mock == nil {
                    Text(app.link.lastError).font(.footnote).foregroundStyle(.red)
                    if app.link.transportReady && !app.link.connected {
                        Button("Re-pair with this app") { app.link.repairAuth() }
                    }
                }
            }
            if app.mock == nil && !app.link.connected {
                Section("Connect") { StickPicker() }
            }
            if app.boardConnected && !app.inputReady {
                Section("Pointer") {
                    Text("Pair the pointer: AssistiveTouch on, then Devices > Bluetooth Devices > Mantiza Hands.")
                    OpenAssistiveTouchButton()
                }
            }
            Section("Calibration") {
                LabeledContent("Pointer", value: calibrationText)
                Button("Calibrate") { calibrating = true }.disabled(!app.inputReady)
            }
            Section("Test") {
                Button("Tap the middle of the screen") { run { try await app.hands.tap(CGPoint(x: 0.5, y: 0.5)) } }
                Button("Go to the Home Screen") { run { try await app.hands.home() } }
                Button("Show the on-screen keyboard") { run { try await app.hands.toggleKeyboard() } }
                if !testResult.isEmpty { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
            }
            .disabled(!app.inputReady)
            Section {
                Button("Forget this stick", role: .destructive) { confirmForget = true }
                    .disabled(app.mock != nil || app.link.pairedID == nil)
            } footer: {
                Text("Erases the stick's pairing. Afterwards remove Mantiza Hands in Settings > Bluetooth too.")
            }
        }
        .navigationTitle("Device")
        .fullScreenCover(isPresented: $calibrating) { CalibrationView() }
        .confirmationDialog("Forget Mantiza Hands?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { Task { await app.link.unpair() } }
        }
    }

    private var calibrationText: String {
        guard let worst = app.hands.calibration.worstError else { return "Not calibrated" }
        return String(format: "Within %.1f%%", worst * 100)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        testResult = "…"
        Task {
            do { try await action(); testResult = "Done" } catch { testResult = error.localizedDescription }
        }
    }
}

/// Nearby sticks from the Bluetooth scan; tapping one connects and pairs it with this phone.
struct StickPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let link = app.link
        if link.bluetooth != .poweredOn {
            Text(link.bluetooth == .unauthorized ? "Allow Bluetooth for Mantiza in Settings." : "Turn on Bluetooth.")
        }
        ForEach(link.found) { stick in
            Button {
                link.pair(stick.id)
            } label: {
                HStack {
                    Text(stick.name)
                    Spacer()
                    if link.connecting && link.pairedID == stick.id { ProgressView() }
                }
            }
        }
        Button(link.scanning ? "Scanning…" : "Scan for Mantiza Hands") { link.scan() }
            .disabled(link.scanning || link.bluetooth != .poweredOn)
    }
}

struct OpenAssistiveTouchButton: View {
    @State private var failed = false

    var body: some View {
        Button("Open AssistiveTouch Devices") {
            Task {
                do { try await AccessibilitySettings.openSettings(for: .assistiveTouchDevices) } catch { failed = true }
            }
        }
        if failed {
            Text("Open Settings > Accessibility > Touch > AssistiveTouch > Devices.").font(.footnote)
        }
    }
}

/// Shown while the stick asks the user to confirm a new pairing secret.
struct PairingCodeView: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pairing code").font(.caption).foregroundStyle(.secondary)
            Text(code).font(.system(size: 34, weight: .bold, design: .monospaced))
            Text("If the stick shows the same code, press A on the stick.").font(.footnote)
        }
    }
}
