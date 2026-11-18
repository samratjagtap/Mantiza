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

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var capture: ScreenCapture
    @EnvironmentObject var pointer: Pointer
    @EnvironmentObject var routines: RoutineStore
    @EnvironmentObject var voice: Voice
    @State private var habitRuns = Shared.history.count
    @ObservedObject private var blocked = BlockedApps.shared
    @ObservedObject private var notes = AppNotes.shared
    @State private var newBlocked = ""

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

                Card("Blocked apps", footer: "Mantiza never opens or works in these apps, whatever the request. Add any app by its name on the Home Screen.") {
                    ForEach(blocked.names, id: \.self) { name in
                        HStack {
                            Text(name).font(Theme.sans(15)).foregroundStyle(Theme.text)
                            Spacer()
                            Button { withAnimation { blocked.remove(name) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.dim).frame(width: 28, height: 28)
                            }
                            .accessibilityLabel("Unblock \(name)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    HStack {
                        TextField("", text: $newBlocked, prompt: Text("Add an app").foregroundStyle(Theme.dim))
                            .font(Theme.sans(15)).foregroundStyle(Theme.text).tint(Theme.magenta)
                            .submitLabel(.done)
                            .onSubmit { blocked.add(newBlocked); newBlocked = "" }
                        Button("Add") { blocked.add(newBlocked); newBlocked = "" }
                            .font(Theme.sans(15, .medium)).foregroundStyle(Theme.green)
                            .disabled(newBlocked.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    ActionRow(title: "Reset to the usual list", color: Theme.dim) { withAnimation { blocked.reset() } }
                }

                Card("App notes", footer: notes.all.isEmpty
                     ? "When a task in an app takes detours, Mantiza writes one short note about the app, and uses it next time."
                     : "Short notes Mantiza wrote after tasks with detours; both brains read them next time. Kept on your iPhone.") {
                    if notes.all.isEmpty {
                        Row(key: "None yet", value: "")
                    }
                    ForEach(notes.all.keys.sorted(), id: \.self) { app in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(app).font(Theme.sans(15, .medium)).foregroundStyle(Theme.text)
                                Spacer()
                                Button { withAnimation { notes.forget(app: app) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.dim).frame(width: 28, height: 28)
                                }
                                .accessibilityLabel("Forget notes about \(app)")
                            }
                            ForEach(notes.notes(for: app), id: \.self) { line in
                                Text(line).font(Theme.sans(13)).foregroundStyle(Theme.dim)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    if !notes.all.isEmpty {
                        ActionRow(title: "Forget all notes", color: Theme.magenta) { withAnimation { notes.forgetAll() } }
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
