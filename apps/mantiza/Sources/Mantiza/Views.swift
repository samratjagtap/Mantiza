import MantizaKit
import SwiftUI

// MARK: - Building blocks (sharp, plain, pixel-flavoured)

/// A titled block with a hairline border and square corners.
struct Panel<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { SectionTag(title) }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

/// "■ DEVICE": a small magenta square and a spaced, uppercase label.
struct SectionTag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.magenta).frame(width: 6, height: 6)
            Text(text.uppercased()).font(Theme.mono(11, .semibold)).tracking(2).foregroundStyle(Theme.dim)
        }
    }
}

/// A square status light.
struct Light: View {
    let on: Bool
    var blink = false
    @State private var dim = false
    var body: some View {
        Rectangle()
            .fill(on ? Theme.green : Theme.magenta)
            .frame(width: 7, height: 7)
            .opacity(blink && dim ? 0.25 : 1)
            .onAppear {
                guard blink else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) { dim = true }
            }
    }
}

/// "KEY ········ VALUE"
struct InfoRow: View {
    let key: String
    let value: String
    var light: Bool?
    var body: some View {
        HStack(spacing: 8) {
            if let light { Light(on: light) }
            Text(key).font(Theme.mono(13)).foregroundStyle(Theme.dim)
            Spacer(minLength: 12)
            Text(value).font(Theme.mono(13)).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
        }
    }
}

/// Solid magenta block button (or outlined), uppercase mono.
struct BlockButtonStyle: ButtonStyle {
    var outlined = false
    var color = Theme.magenta
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(14, .bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(outlined ? color : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(outlined ? Color.clear : color.opacity(enabled ? 1 : 0.35))
            .overlay(Rectangle().stroke(color.opacity(enabled ? 1 : 0.35), lineWidth: outlined ? 1.5 : 0))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The screen background, with a faint pixel grid.
struct Backdrop: View {
    var body: some View {
        Theme.ink
            .overlay(
                Canvas { gc, size in
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x < size.width {
                        var y: CGFloat = 0
                        while y < size.height {
                            gc.fill(Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Theme.line.opacity(0.55)))
                            y += step
                        }
                        x += step
                    }
                }
            )
            .ignoresSafeArea()
    }
}

/// The pixel "MANTIZA" with letters typing in once.
struct Wordmark: View {
    var height: CGFloat = 18
    var body: some View {
        PixelArt(Logo.wordmark, assemble: true).frame(height: height)
    }
}

// MARK: - Task

struct TaskView: View {
    @EnvironmentObject var agent: Agent
    @EnvironmentObject var approvals: Approvals
    @EnvironmentObject var link: DeviceLink
    @Binding var request: String
    @FocusState private var typing: Bool
    @State private var openShot: UUID?

    private let examples = ["Message Azad on WhatsApp: I'm coming", "Set an alarm for 7 AM every weekday",
                            "Timer for 10 minutes", "Turn on the flashlight", "Brightness to 30%",
                            "Remind me to buy milk tomorrow at 9", "Directions to India Gate", "Turn on Do Not Disturb"]

    private var mood: Mood {
        if agent.running { return .working }
        if agent.status.hasPrefix("✅") || agent.status.hasPrefix("💬") { return .done }
        if agent.status.hasPrefix("❌") { return .failed }
        return .idle
    }

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    hero
                    input
                    question
                    if agent.steps.isEmpty && !agent.running { suggestions }
                    if !agent.steps.isEmpty { timeline }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack {
            Wordmark(height: 16)
            Spacer()
            HStack(spacing: 6) {
                Light(on: link.ready, blink: !link.ready)
                Text(link.ready ? "LINKED" : "NO DEVICE").font(Theme.mono(11, .semibold)).tracking(1.5)
                    .foregroundStyle(link.ready ? Theme.green : Theme.magenta)
            }
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            PixelArt(Logo.head, mood: mood).frame(height: 120)
            Text(agent.status)
                .font(Theme.mono(13))
                .foregroundStyle(mood == .failed ? Theme.magenta : Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: agent.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var input: some View {
        Panel("Task") {
            HStack(alignment: .top, spacing: 8) {
                Text(">").font(Theme.mono(16, .bold)).foregroundStyle(Theme.green)
                TextField("", text: $request, prompt: Text("what should mantiza do?").foregroundStyle(Theme.dim),
                          axis: .vertical)
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.green)
                    .lineLimit(1...4)
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit(run)
            }
            if agent.running {
                Button { agent.stop() } label: { Text("■ Stop") }
                    .buttonStyle(BlockButtonStyle(outlined: true))
            } else {
                Button(action: run) { Text("Run ▸") }
                    .buttonStyle(BlockButtonStyle())
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func run() {
        guard !agent.running, !request.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        typing = false
        agent.start(request)
    }

    @ViewBuilder private var question: some View {
        if let q = approvals.question, let choices = approvals.choices {
            Panel("Which one?") {
                Text(q).font(Theme.mono(14)).foregroundStyle(Theme.text)
                ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                    Button { approvals.pick(i) } label: { Text(c).textCase(nil) }
                        .buttonStyle(BlockButtonStyle(outlined: true, color: Theme.green))
                }
                Button("None of these") { approvals.pick(nil) }.buttonStyle(BlockButtonStyle(outlined: true))
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let q = approvals.question {
            Panel("Needs your OK") {
                Text(q).font(Theme.mono(14)).foregroundStyle(Theme.text)
                HStack(spacing: 10) {
                    Button("Approve") { approvals.answer(true) }.buttonStyle(BlockButtonStyle(color: Theme.green))
                    Button("Don't") { approvals.answer(false) }.buttonStyle(BlockButtonStyle(outlined: true))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var suggestions: some View {
        Panel("Try") {
            ForEach(examples, id: \.self) { e in
                Button { request = e } label: {
                    HStack(spacing: 10) {
                        Text("▸").foregroundStyle(Theme.magenta)
                        Text(e).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .font(Theme.mono(13))
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var timeline: some View {
        Panel("Steps") {
            ForEach(Array(agent.steps.enumerated()), id: \.element.id) { i, step in
                let current = agent.running && i == agent.steps.count - 1
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Light(on: !step.text.hasPrefix("❌"), blink: current)
                            .padding(.top, 5)
                        Text(step.text).font(Theme.mono(12)).foregroundStyle(current ? Theme.text : Theme.text.opacity(0.85))
                        Spacer(minLength: 0)
                        if step.image != nil {
                            Button { openShot = openShot == step.id ? nil : step.id } label: {
                                Image(systemName: openShot == step.id ? "eye.slash" : "eye").font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    if let image = step.image, openShot == step.id {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: agent.steps.count)
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var capture: ScreenCapture
    @EnvironmentObject var pointer: Pointer
    @EnvironmentObject var routines: RoutineStore

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        PixelArt(Logo.small, mood: link.ready ? .idle : .failed).frame(height: 30)
                        Text("DEVICE").font(Theme.mono(20, .bold)).tracking(4).foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.top, 8)

                    Panel("StickS3") {
                        InfoRow(key: "Bluetooth", value: link.bluetooth, light: link.bluetooth.lowercased().contains("on"))
                        InfoRow(key: "Link", value: link.status, light: link.ready)
                        InfoRow(key: "Battery", value: link.battery)
                        Button("Connect again") { link.connect() }.buttonStyle(BlockButtonStyle(outlined: true, color: Theme.green))
                        Text("Pair it in iPhone Settings → Bluetooth, with AssistiveTouch on.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }

                    Panel("Pointer") {
                        if link.absolute == true {
                            InfoRow(key: "Mode", value: "absolute · no calibration", light: true)
                        } else {
                            InfoRow(key: "Mode", value: pointer.calibration, light: pointer.calibrated)
                            Button("Calibrate") { pointer.startCalibration() }
                                .buttonStyle(BlockButtonStyle(outlined: true, color: Theme.green))
                                .disabled(!link.ready || pointer.calibrating)
                        }
                    }

                    Panel("Eyes") {
                        InfoRow(key: "Screen sharing", value: capture.state, light: capture.running)
                        HStack(spacing: 10) {
                            Button("Start") { Task { await pointer.startSharing() } }
                                .buttonStyle(BlockButtonStyle(outlined: true, color: Theme.green))
                                .disabled(!link.ready || !pointer.calibrated || capture.running)
                            Button("Stop") { capture.stop() }
                                .buttonStyle(BlockButtonStyle(outlined: true))
                                .disabled(!capture.running)
                        }
                        Text("Stays on between tasks. Locking the phone stops it; the next task starts it again.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }

                    Panel("Learned routines") {
                        if routines.all.isEmpty {
                            Text("None yet. Screen tasks the AI finishes are learned here and replayed without AI.")
                                .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                        }
                        ForEach(routines.all.sorted { $0.learned > $1.learned }) { r in
                            HStack(alignment: .top, spacing: 10) {
                                Light(on: r.replays > 0)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(Theme.mono(13)).foregroundStyle(Theme.text)
                                    Text("\(r.steps.count) step\(r.steps.count == 1 ? "" : "s") · \(r.replays)× without AI")
                                        .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Button { withAnimation { routines.delete(r.name) } } label: {
                                    Text("✕").font(Theme.mono(13)).foregroundStyle(Theme.magenta)
                                }
                            }
                        }
                        if !routines.all.isEmpty {
                            Button("Forget all") { withAnimation { routines.deleteAll() } }
                                .buttonStyle(BlockButtonStyle(outlined: true))
                        }
                    }

                    Panel("Brains") {
                        InfoRow(key: "Fast · Luna Decisions", value: Keys.fastBrainRoute, light: Keys.fastBrainRoute != "missing key")
                        InfoRow(key: "Big · Gemini 3.5 Flash-Lite", value: Keys.gemini.isEmpty ? "missing key" : "AI Studio",
                                light: !Keys.gemini.isEmpty)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .fullScreenCover(isPresented: $pointer.calibrating) { CalibrationCatcher() }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var link: DeviceLink

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        PixelArt(Logo.small, animated: false, assemble: false).frame(height: 22)
                        Text("LOG").font(Theme.mono(20, .bold)).tracking(4).foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    ForEach(link.log) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                                .font(Theme.mono(10)).foregroundStyle(Theme.green.opacity(0.8))
                            Text(line.text).font(Theme.mono(11)).foregroundStyle(Theme.text.opacity(0.9))
                        }
                        .padding(.vertical, 3)
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Boot

/// First thing on launch: the head assembles, the name types in, then the app fades in.
struct BootView: View {
    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 26) {
                PixelArt(Logo.head, mood: .idle).frame(height: 150)
                Wordmark(height: 22)
            }
        }
    }
}
