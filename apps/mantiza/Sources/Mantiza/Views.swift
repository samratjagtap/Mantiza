import MantizaKit
import SwiftUI

// Mantiza's screens: minimal and calm. Plain dark background, clean system type, soft cards,
// magenta only for the main action, green only for "connected / done", and the pixel head as the
// one decorative element.

// MARK: - Building blocks

/// A small grey label above a group ("STEPS", "STICKS3").
struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

/// A group of rows on a soft card, like iOS Settings. Rows are separated by hairlines.
struct Card<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Label2(title) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 16) }
                        row
                    }
                }
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            if let footer {
                Text(footer).font(Theme.sans(12)).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
    }
}

/// "Battery ............ 84%" with an optional status dot.
struct Row: View {
    let key: String
    let value: String
    var dot: Bool?
    var body: some View {
        HStack(spacing: 10) {
            Text(key).font(Theme.sans(15)).foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            if let dot { Dot(on: dot) }
            Text(value).font(Theme.sans(15)).foregroundStyle(Theme.dim).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// A tappable row inside a card ("Connect again").
struct ActionRow: View {
    let title: String
    var color = Theme.text
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.sans(15, .medium))
                .foregroundStyle(color.opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressRow())
    }
}

struct PressRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.raised : .clear)
    }
}

/// A small round status dot; it breathes while something is in progress.
struct Dot: View {
    let on: Bool
    var color: Color? = nil
    var pulse = false
    @State private var dim = false
    var body: some View {
        Circle()
            .fill(color ?? (on ? Theme.green : Theme.dim.opacity(0.6)))
            .frame(width: 7, height: 7)
            .opacity(pulse && dim ? 0.3 : 1)
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { dim = true }
            }
    }
}

/// Full-width buttons: filled (the main action) or quiet.
struct MainButton: ButtonStyle {
    var filled = true
    var color = Theme.magenta
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(15, .semibold))
            .foregroundStyle(filled ? .white : Theme.text)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(filled ? color : Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
    }
}

/// A screen's title ("Device", "Log").
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.sans(30, .bold)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }
}

// MARK: - Task

struct TaskView: View {
    @EnvironmentObject var agent: Agent
    @EnvironmentObject var approvals: Approvals
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var listener: Listener
    @Binding var request: String
    @FocusState private var typing: Bool
    @State private var openShot: UUID?
    /// What you usually ask around now first, then recent tasks, then starters.
    @State private var ideas: [Shared.Suggestion] = []

    private var mood: Mood {
        if agent.running { return .working }
        if agent.status.hasPrefix("✅") || agent.status.hasPrefix("💬") { return .done }
        if agent.status.hasPrefix("❌") { return .failed }
        return .idle
    }

    private var empty: Bool { request.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                hero
                input
                question
                if agent.steps.isEmpty && !agent.running { suggestions }
                if !agent.steps.isEmpty { timeline }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .animation(.easeOut(duration: 0.2), value: approvals.question)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ink.ignoresSafeArea())
        .onAppear { ideas = Shared.suggestions(count: 5) }
        .onChange(of: agent.running) { _, running in if !running { ideas = Shared.suggestions(count: 5) } }
        // While listening, the words appear in the field as they are heard.
        .onChange(of: listener.heard) { _, heard in if listener.listening { request = heard } }
    }

    private var header: some View {
        HStack {
            PixelArt(Logo.wordmark, animated: false).frame(height: 11)
            Spacer()
            HStack(spacing: 6) {
                Dot(on: link.ready, pulse: !link.ready)
                Text(link.ready ? "Connected" : "No device").font(Theme.sans(13)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.top, 10)
    }

    private var hero: some View {
        VStack(spacing: 18) {
            PixelArt(Logo.head, mood: mood).frame(height: 76)
            Text(listener.listening ? "Listening…" : (listener.problem ?? agent.status))
                .font(Theme.sans(16))
                .foregroundStyle(mood == .failed || listener.problem != nil ? Theme.magenta : Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: agent.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // One rounded field with the send (or stop) button inside it.
    private var input: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $request, prompt: Text("Ask Mantiza…").foregroundStyle(Theme.dim), axis: .vertical)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .tint(Theme.magenta)
                .lineLimit(1...5)
                .focused($typing)
                .submitLabel(.go)
                .onSubmit(run)
                .padding(.vertical, 7)
            // One button: stop while a task runs; the microphone while the field is empty (or
            // while listening); send once there is text.
            let mic = !agent.running && (empty || listener.listening)
            Button {
                if agent.running { agent.stop() } else if mic { typing = false; listener.toggle() } else { run() }
            } label: {
                Image(systemName: agent.running ? "stop.fill" : (mic ? "mic.fill" : "arrow.up"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(agent.running ? Theme.ink : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(agent.running ? Theme.text : (mic && !listener.listening ? Theme.raised : Theme.magenta)))
                    .scaleEffect(listener.listening ? 1.12 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: listener.listening)
            }
            .accessibilityLabel(agent.running ? "Stop" : (mic ? (listener.listening ? "Stop listening" : "Speak") : "Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(typing ? Theme.magenta.opacity(0.6) : Theme.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: typing)
    }

    private func run() {
        guard !agent.running, !empty else { return }
        typing = false
        listener.finish(run: false)
        agent.start(request)
    }

    @ViewBuilder private var question: some View {
        if let q = approvals.question {
            VStack(alignment: .leading, spacing: 14) {
                Text(approvals.choices == nil ? "Needs your OK" : "Which one?")
                    .font(Theme.mono(11, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.dim)
                Text(q).font(Theme.sans(16)).foregroundStyle(Theme.text)
                if let choices = approvals.choices {
                    ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                        Button(c) { approvals.pick(i) }.buttonStyle(MainButton(filled: false))
                    }
                    Button("None of these") { approvals.pick(nil) }
                        .font(Theme.sans(14)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 10) {
                        Button("Not now") { approvals.answer(false) }.buttonStyle(MainButton(filled: false))
                        Button("Approve") { approvals.answer(true) }.buttonStyle(MainButton())
                    }
                }
            }
            .padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(ideas.contains { $0.habit } ? "Usually around now" : "Try")
            ForEach(ideas, id: \.self) { idea in
                Button { request = idea.prompt } label: {
                    HStack(spacing: 8) {
                        if idea.habit { Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(Theme.green) }
                        Text(idea.prompt).font(Theme.sans(15)).foregroundStyle(Theme.text.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label2("Steps")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(agent.steps.enumerated()), id: \.element.id) { i, step in
                    let current = agent.running && i == agent.steps.count - 1
                    let failed = step.text.hasPrefix("❌")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Dot(on: true, color: failed ? Theme.magenta : (current ? Theme.text : Theme.green.opacity(0.8)),
                                pulse: current)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(step.text).font(Theme.sans(14))
                                .foregroundStyle(current ? Theme.text : Theme.text.opacity(0.7))
                            Spacer(minLength: 0)
                            if step.image != nil {
                                Button { withAnimation(.easeOut(duration: 0.2)) { openShot = openShot == step.id ? nil : step.id } } label: {
                                    Image(systemName: openShot == step.id ? "photo.fill" : "photo")
                                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                        if let image = step.image, openShot == step.id {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 380)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.leading, 19)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
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
    @EnvironmentObject var voice: Voice
    @State private var habitRuns = Shared.history.count

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ScreenTitle(text: "Device")

                Card("StickS3", footer: "Pair it in iPhone Settings → Bluetooth, with AssistiveTouch on. For Siri tasks, turn on Settings → Accessibility → Siri → Type to Siri.") {
                    Row(key: "Bluetooth", value: link.bluetooth, dot: link.bluetooth.lowercased().contains("on"))
                    Row(key: "Connection", value: link.status, dot: link.ready)
                    Row(key: "Battery", value: link.battery)
                    ActionRow(title: "Connect again", color: Theme.green) { link.connect() }
                }

                Card("Pointer") {
                    if link.absolute == true {
                        Row(key: "Mode", value: "Absolute", dot: true)
                    } else {
                        Row(key: "Mode", value: pointer.calibration, dot: pointer.calibrated)
                        ActionRow(title: "Calibrate", color: Theme.green) { pointer.startCalibration() }
                            .disabled(!link.ready || pointer.calibrating)
                    }
                }

                Card("Screen sharing", footer: "Stays on between tasks. Locking the phone stops it; the next task starts it again.") {
                    Row(key: "Status", value: capture.state, dot: capture.running)
                    if capture.running {
                        ActionRow(title: "Stop sharing", color: Theme.magenta) { capture.stop() }
                    } else {
                        ActionRow(title: "Start sharing", color: Theme.green) { Task { await pointer.startSharing() } }
                            .disabled(!link.ready || !pointer.calibrated)
                    }
                }

                Card("Learned routines", footer: routines.all.isEmpty
                     ? "Screen tasks the AI finishes are learned here and then replayed without AI." : nil) {
                    if routines.all.isEmpty {
                        Row(key: "None yet", value: "")
                    }
                    ForEach(routines.all.sorted { $0.learned > $1.learned }) { r in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(Theme.sans(15)).foregroundStyle(Theme.text)
                                Text("\(r.steps.count) step\(r.steps.count == 1 ? "" : "s") · replayed \(r.replays)×")
                                    .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button { withAnimation { routines.delete(r.name) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.dim).frame(width: 28, height: 28)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    if !routines.all.isEmpty {
                        ActionRow(title: "Forget all", color: Theme.magenta) { withAnimation { routines.deleteAll() } }
                    }
                }

                Card("Voice", footer: "Mantiza says the result out loud, also when the ring switch is on silent. Say \"Hey Siri, ask Mantiza\", or tap the microphone on the Task screen.") {
                    HStack {
                        Text("Speak results").font(Theme.sans(15)).foregroundStyle(Theme.text)
                        Spacer()
                        Picker("Speak results", selection: $voice.mode) {
                            ForEach(SpeakMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.dim)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                Card("Habits", footer: "Mantiza remembers which tasks worked and when, to offer them at the right time in the app and the widget. This stays on your iPhone.") {
                    Row(key: "Tasks remembered", value: "\(habitRuns)")
                    if habitRuns > 0 {
                        ActionRow(title: "Forget habits", color: Theme.magenta) {
                            Shared.forgetHabits()
                            habitRuns = 0
                        }
                    }
                }

                Card("Brains") {
                    Row(key: "Fast", value: Keys.fastBrainRoute == "missing key" ? "Missing key" : "Luna Decisions",
                        dot: Keys.fastBrainRoute != "missing key")
                    Row(key: "Big", value: Keys.gemini.isEmpty ? "Missing key" : "Gemini 3.5 Flash-Lite",
                        dot: !Keys.gemini.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Theme.ink.ignoresSafeArea())
        .fullScreenCover(isPresented: $pointer.calibrating) { CalibrationCatcher() }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var link: DeviceLink

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "Log").padding(.bottom, 14)
                if link.log.isEmpty {
                    Text("Nothing yet.").font(Theme.sans(15)).foregroundStyle(Theme.dim)
                }
                ForEach(link.log) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(line.time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        Text(line.text).font(Theme.mono(12)).foregroundStyle(Theme.text.opacity(0.85))
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Theme.ink.ignoresSafeArea())
    }
}

// MARK: - Boot

/// App start: the head is there at once, flicks its antennae and blinks twice (~1 s), then the app.
struct BootView: View {
    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            PixelArt(Logo.head, mood: .greeting).frame(height: 96)
        }
    }
}
