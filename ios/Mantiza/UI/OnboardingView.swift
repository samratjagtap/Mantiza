import SwiftUI

/// First-run setup. Order matters: the app connects to the stick first, then the user pairs the pointer in
/// AssistiveTouch (iOS keeps both links only in that order), then calibration and the AI keys.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step = Step.welcome
    @State private var calibrating = false

    enum Step: Int, CaseIterable { case welcome, connect, pointer, settings, calibrate, keys, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
            ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
            footer
        }
        .padding(24)
        .onChange(of: app.boardConnected) { _, up in if up && step == .connect { advance() } }
        .onChange(of: app.inputReady) { _, ready in if ready && step == .pointer { advance() } }
        .fullScreenCover(isPresented: $calibrating) {
            CalibrationView { ok in if ok { advance() } }
        }
        .onAppear { Log.event("onboarding.step", ["step": "\(step)"]) }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            Page(title: "Welcome to Mantiza", symbol: "hand.tap") {
                Text("Mantiza does tasks on this iPhone for you, like sending a message or opening a map. Its stick, Mantiza Hands, taps and types the way you would.")
                Text("While a task runs, Mantiza shares your screen with the AI services you choose: Anthropic (Claude) or Google (Gemini), and the quick picker (Laya on your own server, or TypeSafe's Jev). It asks before sending, deleting or buying anything.")
                    .foregroundStyle(.secondary)
            }
        case .connect:
            Page(title: "Connect the stick", symbol: "antenna.radiowaves.left.and.right") {
                Text("Turn on Mantiza Hands and keep it close. Tap it below, then allow pairing.")
                List { StickPicker() }.frame(minHeight: 200).listStyle(.insetGrouped)
                if let code = app.link.pairingCode { PairingCodeView(code: code) }
                if !app.link.lastError.isEmpty { Text(app.link.lastError).font(.footnote).foregroundStyle(.red) }
                if app.boardConnected { Label("Connected to \(app.boardName)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        case .pointer:
            Page(title: "Turn on the pointer", symbol: "cursorarrow.rays") {
                Text("1. Tap the button below. It opens AssistiveTouch.")
                Text("2. Turn on AssistiveTouch, open Devices > Bluetooth Devices and tap Mantiza Hands.")
                Text("3. Come back here. This page moves on by itself.")
                OpenAssistiveTouchButton().buttonStyle(.borderedProminent)
                if app.inputReady { Label("Pointer ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        case .settings:
            Page(title: "A few settings", symbol: "gearshape") {
                Text("These keep taps accurate:")
                Text("• Portrait Orientation Lock on (Control Centre).")
                Text("• AssistiveTouch: drag its round button to a corner and keep it there.")
                Text("• Pointer Control: Automatically Hide off, Pointer Animations off.")
                Text("• Display Zoom: Default (Settings > Display & Brightness).")
            }
        case .calibrate:
            Page(title: "Calibrate", symbol: "scope") {
                Text("The stick taps a few points on a grid so Mantiza knows exactly where its taps land. It takes about 20 seconds.")
                if app.calibrated { Label("Calibrated", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        case .keys:
            Page(title: "AI keys", symbol: "key") {
                KeysForm()
            }
        case .done:
            Page(title: "All set", symbol: "checkmark.seal") {
                Text("Ask Mantiza for something on the Run tab. You can redo any of these steps from the Device tab.")
            }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if step != .welcome { Button("Back") { move(-1) } }
            Spacer()
            switch step {
            case .connect where !app.boardConnected, .pointer where !app.inputReady:
                Button("Skip") { advance() }
            case .calibrate where !app.calibrated:
                Button("Skip") { advance() }
                Button("Calibrate") { calibrating = true }.buttonStyle(.borderedProminent).disabled(!app.inputReady)
            case .done:
                Button("Start using Mantiza") { app.onboarded = true }.buttonStyle(.borderedProminent)
            default:
                Button("Continue") { advance() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func advance() { move(1) }

    private func move(_ by: Int) {
        step = Step(rawValue: min(max(step.rawValue + by, 0), Step.done.rawValue)) ?? .done
        Log.event("onboarding.step", ["step": "\(step)"])
    }
}

private struct Page<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            content
        }
    }
}
