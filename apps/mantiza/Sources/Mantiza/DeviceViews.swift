import MantizaKit
import SwiftUI

// The Device tab: the StickS3 at a glance (status, three tiles, the one action that matters now),
// a setup checklist only while something is missing, then Mantiza's settings and memory as short
// rows that open their own pages.

// MARK: - Device tab

struct DeviceView: View {
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var capture: ScreenCapture
    @EnvironmentObject var pointer: Pointer
    @EnvironmentObject var routines: RoutineStore
    @EnvironmentObject var voice: Voice
    @ObservedObject private var chime = Chime.shared
    @ObservedObject private var schedules = Schedules.shared
    @ObservedObject private var blocked = BlockedApps.shared
    @ObservedObject private var notes = AppNotes.shared
    @State private var habitRuns = Shared.history.count

    enum Page: Hashable { case setup, schedules, routines, notes, blocked, habits }

    private var bluetoothOn: Bool { link.bluetooth.lowercased().contains("on") }
    // Setup steps iOS can't check (AssistiveTouch's status was wrong on iOS 27): the user ticks them.
    @AppStorage("setup.assistiveTouch") private var assistiveTouchDone = false
    @AppStorage("setup.typeToSiri") private var typeToSiriDone = false
    private var setupDone: Int { [link.ready, assistiveTouchDone, typeToSiriDone, pointer.calibrated].filter { $0 }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScreenTitle(text: "Device")
                    deviceCard
                    setupRow
                    settings
                    brains
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .setup: SetupPage()
                case .routines: RoutinesPage()
                case .notes: NotesPage()
                case .blocked: BlockedPage()
                case .habits: HabitsPage(runs: $habitRuns)
                case .schedules: SchedulesPage()
                }
            }
        }
        .tint(Theme.text)
        .fullScreenCover(isPresented: $pointer.calibrating) { CalibrationCatcher() }
        .onAppear {
            habitRuns = Shared.history.count
        }
    }

    // MARK: The StickS3

    private var headline: String {
        if !bluetoothOn { return "Bluetooth is \(link.bluetooth.lowercased())" }
        if link.ready { return "Connected" }
        return link.status
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised)
                    PixelArt(Logo.head, mood: link.ready ? .idle : .failed, animated: link.ready).frame(height: 28)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text("StickS3").font(Theme.sans(19, .semibold)).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        Dot(on: link.ready, color: link.ready ? Theme.green : (bluetoothOn ? Theme.dim : Theme.magenta), pulse: !link.ready && bluetoothOn)
                        Text(headline).font(Theme.sans(13)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Tile(icon: batteryIcon, title: "Battery", value: link.ready ? link.battery : "–", good: link.ready)
                Tile(icon: "cursorarrow", title: "Pointer", value: pointerValue, good: pointer.calibrated)
                Tile(icon: capture.running ? "eye" : "eye.slash", title: "Screen", value: capture.running ? "Sharing" : "Off",
                     good: capture.running)
            }

            if pointer.calibration.hasPrefix("Failed") {
                Text(pointer.calibration).font(Theme.sans(12)).foregroundStyle(Theme.magenta)
            }

            actions
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }

    private var pointerValue: String {
        if link.absolute == true { return "Exact" }
        return pointer.calibrated ? "Calibrated" : "Not set"
    }

    private var batteryIcon: String {
        let level = Int(link.battery.filter(\.isNumber)) ?? -1
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        case 0..<13: return "battery.0"
        default: return "battery.0"
        }
    }

    /// The one thing to do now, big; the rest quiet.
    @ViewBuilder private var actions: some View {
        if !link.ready {
            Button("Connect") { link.connect() }.buttonStyle(MainButton()).disabled(!bluetoothOn)
        } else if !pointer.calibrated {
            Button("Calibrate the pointer") { pointer.startCalibration() }.buttonStyle(MainButton())
                .disabled(pointer.calibrating)
        } else {
            HStack(spacing: 10) {
                if capture.running {
                    Button("Stop sharing") { capture.stop() }.buttonStyle(MainButton(filled: false))
                } else {
                    Button("Start sharing") { Task { await pointer.startSharing() } }.buttonStyle(MainButton(filled: false))
                }
                if link.absolute != true {
                    Button("Recalibrate") { pointer.startCalibration() }.buttonStyle(MainButton(filled: false))
                        .disabled(pointer.calibrating)
                }
            }
        }
    }

    // MARK: Setup: its own card above the settings, so it is easy to find

    private var setupRow: some View {
        let all = setupDone == 4
        return NavigationLink(value: Page.setup) {
            HStack(spacing: 12) {
                Image(systemName: all ? "checkmark.seal" : "checklist")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(all ? Theme.green : Theme.text)
                    .frame(width: 34, height: 34)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup and help").font(Theme.sans(16, .semibold)).foregroundStyle(Theme.text)
                    Text(all ? "All set" : "\(setupDone) of 4 done").font(Theme.sans(12)).foregroundStyle(Theme.dim)
                }
                Spacer()
                if all {
                    Dot(on: true)
                } else {
                    Text("\(4 - setupDone) left")
                        .font(Theme.sans(12, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.magenta, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(all ? Theme.line : Theme.magenta.opacity(0.5), lineWidth: all ? 0.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Settings and memory

    private var settings: some View {
        Card("Mantiza") {
            // A menu row: one line, short value, the full choices in the menu.
            Menu {
                Picker("Speak results", selection: $voice.mode) {
                    ForEach(SpeakMode.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 12) {
                    Icon("speaker.wave.2")
                    Text("Speak results").font(Theme.sans(15)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(voice.mode.short).font(Theme.sans(15)).foregroundStyle(Theme.dim).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressRow())
            HStack(spacing: 12) {
                Icon("bell")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sounds").font(Theme.sans(15)).foregroundStyle(Theme.text)
                    Text("A soft sound when a task is done or fails").font(Theme.sans(12)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
                Toggle("Sounds", isOn: $chime.on).labelsHidden().tint(Theme.green)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            NavRow(icon: "calendar.badge.clock", title: "Schedules", value: count(schedules.all.count), page: Page.schedules)
            NavRow(icon: "arrow.triangle.2.circlepath", title: "Learned routines", value: count(routines.all.count), page: Page.routines)
            NavRow(icon: "note.text", title: "App notes", value: count(notes.all.count), page: Page.notes)
            NavRow(icon: "hand.raised", title: "Blocked apps", value: "\(blocked.names.count)", page: Page.blocked)
            NavRow(icon: "clock", title: "Habits", value: count(habitRuns), page: Page.habits)
        }
    }

    private func count(_ n: Int) -> String { n == 0 ? "None" : "\(n)" }

    private var brains: some View {
        Card("AI") {
            Row(key: "Fast brain", value: Keys.fastBrainRoute == "missing key" ? "Missing key" : "Luna Decisions",
                dot: Keys.fastBrainRoute != "missing key")
            Row(key: "Big brain", value: Keys.gemini.isEmpty ? "Missing key" : "Gemini 3.5 Flash-Lite", dot: !Keys.gemini.isEmpty)
        }
    }
}

// MARK: - Pieces

/// A small status tile: icon, value, label.
private struct Tile: View {
    let icon: String
    let title: String
    let value: String
    var good = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(good ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                Text(title).font(Theme.sans(11)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A row's icon in a small rounded square.
private struct Icon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image(systemName: name).font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: 28, height: 28)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A row that opens a page: icon, title, value, chevron.
private struct NavRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    let page: DeviceView.Page
    var body: some View {
        NavigationLink(value: page) {
            HStack(spacing: 12) {
                Icon(icon)
                Text(title).font(Theme.sans(15)).foregroundStyle(Theme.text)
                Spacer()
                if let value { Text(value).font(Theme.sans(15)).foregroundStyle(Theme.dim) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressRow())
    }
}

/// A setup step: a tick when done, the way to do it when not.
private struct Check: View {
    let title: String
    let detail: String
    let done: Bool
    /// A step Mantiza can't check: tapping the row ticks or unticks it.
    var toggle: (() -> Void)? = nil
    var body: some View {
        if let toggle {
            Button { withAnimation(.easeOut(duration: 0.15)) { toggle() } } label: { row }
                .buttonStyle(PressRow())
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(done ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.sans(15)).foregroundStyle(done ? Theme.dim : Theme.text)
                if !done {
                    Text(detail + (toggle == nil ? "" : " Tap to tick when done."))
                        .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// A trailing remove button.
private struct RemoveButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle").font(.system(size: 17)).foregroundStyle(Theme.dim)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(label)
    }
}

/// A sub-page: title, the same dark background, cards.
private struct Page<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(Theme.ink.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
    }
}

/// An empty list: one calm line.
private struct Empty: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.sans(14)).foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

// MARK: - Pages

private struct SetupPage: View {
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var pointer: Pointer
    @AppStorage("setup.assistiveTouch") private var assistiveTouchDone = false
    @AppStorage("setup.typeToSiri") private var typeToSiriDone = false
    var body: some View {
        Page(title: "Setup and help") {
            Card("Set up once", footer: "Steps 1 and 4 tick themselves. iOS can't tell Mantiza about 2 and 3, so tick them when you've turned them on.") {
                Check(title: "1. Pair the StickS3", detail: "Settings → Bluetooth → Mantiza. It works as the iPhone's mouse and keyboard.",
                      done: link.ready)
                Check(title: "2. Turn on AssistiveTouch", detail: "Settings → Accessibility → Touch → AssistiveTouch. The pointer only shows with it on.",
                      done: assistiveTouchDone, toggle: { assistiveTouchDone.toggle() })
                Check(title: "3. Turn on Type to Siri", detail: "Settings → Accessibility → Siri → Type to Siri. Mantiza types its Siri requests.",
                      done: typeToSiriDone, toggle: { typeToSiriDone.toggle() })
                Check(title: "4. Calibrate the pointer", detail: "Device tab → Calibrate. The StickS3 clicks 3 spots; don't touch the screen.",
                      done: pointer.calibrated)
            }
            Card("StickS3") {
                Row(key: "Bluetooth", value: link.bluetooth, dot: link.bluetooth.lowercased().contains("on"))
                Row(key: "Connection", value: link.status, dot: link.ready)
                ActionRow(title: "Connect again", color: Theme.green) { link.connect() }
            }
            Card("Screen sharing", footer: "Mantiza starts it only when a task needs to see the screen. It stays on between tasks; locking the phone stops it.") {
                Row(key: "When", value: "Only when needed")
            }
        }
    }
}

private struct RoutinesPage: View {
    @EnvironmentObject var routines: RoutineStore
    var body: some View {
        Page(title: "Learned routines") {
            Text("Screen tasks the AI finished are saved here and replayed next time without AI. Remove one if it learned something wrong.")
                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
            if routines.all.isEmpty {
                Empty(text: "None yet.")
            } else {
                Card {
                    ForEach(routines.all.sorted { $0.learned > $1.learned }) { r in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(Theme.sans(15)).foregroundStyle(Theme.text)
                                Text("\(r.steps.count) step\(r.steps.count == 1 ? "" : "s") · replayed \(r.replays)×")
                                    .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            RemoveButton(label: "Forget \(r.name)") { withAnimation { routines.delete(r.name) } }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .padding(.vertical, 9)
                    }
                }
                Button("Forget all routines") { withAnimation { routines.deleteAll() } }
                    .font(Theme.sans(15, .medium)).foregroundStyle(Theme.magenta)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct NotesPage: View {
    @ObservedObject private var notes = AppNotes.shared
    var body: some View {
        Page(title: "App notes") {
            Text("When a task in an app takes detours, Mantiza writes one short note about that app and reads it next time. Kept on this iPhone.")
                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
            if notes.all.isEmpty {
                Empty(text: "None yet.")
            } else {
                ForEach(notes.all.keys.sorted(), id: \.self) { app in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label2(app)
                            Button("Forget") { withAnimation { notes.forget(app: app) } }
                                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(notes.notes(for: app), id: \.self) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(Theme.dim)
                                    Text(line).font(Theme.sans(14)).foregroundStyle(Theme.text.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }
                }
                Button("Forget all notes") { withAnimation { notes.forgetAll() } }
                    .font(Theme.sans(15, .medium)).foregroundStyle(Theme.magenta)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct BlockedPage: View {
    @ObservedObject private var blocked = BlockedApps.shared
    @State private var newName = ""
    @FocusState private var typing: Bool

    var body: some View {
        Page(title: "Blocked apps") {
            Text("Mantiza never opens or works in these apps, whatever the request: money, passwords and codes. Add any app by its name on the Home Screen.")
                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
            HStack(spacing: 10) {
                TextField("", text: $newName, prompt: Text("Add an app").foregroundStyle(Theme.dim))
                    .font(Theme.sans(15)).foregroundStyle(Theme.text).tint(Theme.magenta)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add", action: add)
                    .font(Theme.sans(15, .semibold)).foregroundStyle(Theme.green)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(typing ? Theme.magenta.opacity(0.6) : Theme.line, lineWidth: 1))
            Card {
                ForEach(blocked.names, id: \.self) { name in
                    HStack {
                        Text(name).font(Theme.sans(15)).foregroundStyle(Theme.text)
                        Spacer()
                        RemoveButton(label: "Unblock \(name)") { withAnimation { blocked.remove(name) } }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                }
            }
            Button("Reset to the usual list") { withAnimation { blocked.reset() } }
                .font(Theme.sans(15, .medium)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity)
        }
    }

    private func add() {
        withAnimation { blocked.add(newName) }
        newName = ""
    }
}

private struct HabitsPage: View {
    @Binding var runs: Int
    var body: some View {
        Page(title: "Habits") {
            Text("Mantiza remembers which tasks worked and when, to offer them at the right time in the app and the widget. This stays on your iPhone.")
                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
            Card {
                Row(key: "Tasks remembered", value: "\(runs)")
            }
            if runs > 0 {
                Button("Forget habits") {
                    Shared.forgetHabits()
                    runs = 0
                }
                .font(Theme.sans(15, .medium)).foregroundStyle(Theme.magenta)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Schedules

private struct SchedulesPage: View {
    @ObservedObject private var schedules = Schedules.shared
    @State private var prompt = ""
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var days: Set<Int> = []
    @State private var open: UUID?
    @FocusState private var typing: Bool

    private var empty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Page(title: "Schedules") {
            Text("Mantiza does a task at a set time. Then you get a notification: tap it and Mantiza does it. You can also say it in a chat: \u{201C}every morning at 8, read my calendar\u{201D}.")
                .font(Theme.sans(13)).foregroundStyle(Theme.dim)
            if schedules.notificationsAllowed == false { notificationsOff }
            newSchedule
            if schedules.all.isEmpty {
                Empty(text: "No schedules yet.")
            } else {
                ForEach(schedules.all) { s in
                    ScheduleCard(schedule: s, open: $open)
                }
            }
        }
        .task { await schedules.refreshPermission() }
    }

    private var notificationsOff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifications are off for Mantiza, so schedules can't remind you. Turn them on in Settings \u{2192} Notifications \u{2192} Mantiza.")
                .font(Theme.sans(14)).foregroundStyle(Theme.text)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(Theme.sans(14, .semibold)).foregroundStyle(Theme.magenta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
    }

    private var newSchedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label2("New schedule")
            TextField("", text: $prompt, prompt: Text("What should Mantiza do?").foregroundStyle(Theme.dim), axis: .vertical)
                .font(Theme.sans(15)).foregroundStyle(Theme.text).tint(Theme.magenta)
                .lineLimit(1...3)
                .focused($typing)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Text("Time").font(Theme.sans(15)).foregroundStyle(Theme.text)
                Spacer()
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            DayPicker(days: $days)
            Button("Add schedule") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                withAnimation {
                    schedules.add(prompt: prompt, hour: c.hour ?? 8, minute: c.minute ?? 0, days: Array(days))
                }
                prompt = ""
                days = []
                typing = false
            }
            .buttonStyle(MainButton())
            .disabled(empty)
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Seven round day buttons in the phone's week order; none picked means every day.
private struct DayPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        let cal = Calendar.current
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { day in
                    let on = days.contains(day)
                    Button {
                        if on { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(cal.veryShortWeekdaySymbols[day - 1])
                            .font(Theme.sans(13, .semibold))
                            .foregroundStyle(on ? .white : Theme.dim)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(Circle().fill(on ? Theme.magenta : Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cal.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(Schedules.describe(Array(days))).font(Theme.sans(12)).foregroundStyle(Theme.dim)
        }
    }
}

private struct ScheduleCard: View {
    @EnvironmentObject var agent: Agent
    @ObservedObject private var schedules = Schedules.shared
    let schedule: Schedules.Schedule
    @Binding var open: UUID?
    @State private var copied = false

    private var expanded: Bool { open == schedule.id }

    private func set(_ change: (inout Schedules.Schedule) -> Void) {
        var s = schedule
        change(&s)
        withAnimation(.easeOut(duration: 0.15)) { schedules.update(s) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Schedules.time(schedule.hour, schedule.minute))
                        .font(Theme.sans(24, .semibold))
                        .foregroundStyle(schedule.on ? Theme.text : Theme.dim)
                    Text(Schedules.describe(schedule.days) + " \u{00B7} " + (schedule.handsFree ? "Runs by itself" : "Reminder"))
                        .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Toggle("On", isOn: Binding(get: { schedule.on }, set: { v in set { $0.on = v } }))
                    .labelsHidden().tint(Theme.green)
            }
            Text(schedule.prompt).font(Theme.sans(15)).foregroundStyle(Theme.text.opacity(schedule.on ? 0.9 : 0.5))
                .fixedSize(horizontal: false, vertical: true)
            Button { withAnimation(.easeOut(duration: 0.2)) { open = expanded ? nil : schedule.id } } label: {
                HStack(spacing: 5) {
                    Text(expanded ? "Fewer options" : "Options").font(Theme.sans(13))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            if expanded { options }
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    @ViewBuilder private var options: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5)
        Toggle(isOn: Binding(get: { schedule.handsFree }, set: { v in set { $0.handsFree = v } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run by itself").font(Theme.sans(15)).foregroundStyle(Theme.text)
                Text("No tap needed. Set up once in the Shortcuts app.").font(Theme.sans(12)).foregroundStyle(Theme.dim)
            }
        }
        .tint(Theme.green)
        if schedule.handsFree {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").font(Theme.mono(12, .medium)).foregroundStyle(Theme.dim)
                        Text(step).font(Theme.sans(13)).foregroundStyle(Theme.text.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy link") {
                    UIPasteboard.general.string = schedule.link.absoluteString
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
                .buttonStyle(MainButton(filled: false))
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
                .buttonStyle(MainButton(filled: false))
            }
            Text("Mantiza sends no reminder for this one. It works on the screen only while the iPhone is unlocked. Deleting the schedule here doesn't delete the Shortcuts automation.")
                .font(Theme.sans(12)).foregroundStyle(Theme.dim)
        }
        HStack(spacing: 10) {
            Button("Run now") { agent.start(schedule.prompt) }
                .buttonStyle(MainButton(filled: false))
                .disabled(agent.running)
            Button { withAnimation { schedules.delete(schedule.id) } } label: {
                Text("Delete").font(Theme.sans(15, .semibold)).foregroundStyle(Theme.magenta)
                    .padding(.vertical, 13).frame(maxWidth: .infinity)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var steps: [String] {
        let time = Schedules.time(schedule.hour, schedule.minute)
        let days = Schedules.describe(schedule.days)
        return [
            "Tap Copy link below.",
            "Open Shortcuts \u{2192} Automation \u{2192} + \u{2192} Time of Day.",
            "Set \(time), repeat \(days.lowercased()). Choose Run Immediately, then Next.",
            "Create New Shortcut (or New Blank Automation) \u{2192} Add Action \u{2192} search \u{201C}Open URLs\u{201D}.",
            "Paste the link into the action, then tap Done.",
        ]
    }
}
