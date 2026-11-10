import SwiftUI

// MARK: - Task

struct TaskView: View {
    @EnvironmentObject var agent: Agent
    @EnvironmentObject var approvals: Approvals
    @State private var request = ""
    @FocusState private var typing: Bool

    private let examples = ["Message Azad on WhatsApp: I'm coming", "Set an alarm for 7 AM every weekday",
                            "Timer for 10 minutes", "Turn on the flashlight", "Brightness to 30%",
                            "Remind me to buy milk tomorrow at 9", "Call Azad", "Directions to India Gate",
                            "Volume up", "Turn on Do Not Disturb", "Turn off Wi-Fi"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("What should Mantiza do?", text: $request, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($typing)
                    if agent.running {
                        Button(role: .destructive) { agent.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    } else {
                        Button {
                            typing = false
                            agent.start(request)
                        } label: { Label("Go", systemImage: "play.fill") }
                        .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text(agent.status)
                }

                if let q = approvals.question {
                    Section("Needs your OK") {
                        Text(q)
                        HStack {
                            Button("Approve") { approvals.answer(true) }.buttonStyle(.borderedProminent)
                            Button("Don't", role: .destructive) { approvals.answer(false) }.buttonStyle(.bordered)
                        }
                    }
                }

                if agent.steps.isEmpty && !agent.running {
                    Section("Try") {
                        ForEach(examples, id: \.self) { e in
                            Button(e) { request = e }
                        }
                    }
                }

                if !agent.steps.isEmpty {
                    Section("Steps") {
                        ForEach(agent.steps) { step in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.text).font(.callout)
                                if let image = step.image {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mantiza")
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var capture: ScreenCapture
    @EnvironmentObject var pointer: Pointer
    @EnvironmentObject var routines: RoutineStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bluetooth", value: link.bluetooth)
                    LabeledContent("Device", value: link.status)
                    LabeledContent("Battery", value: link.battery)
                    Button("Connect again") { link.connect() }
                } header: { Text("1 · Device") } footer: {
                    Text("The device must be paired in iPhone Settings → Bluetooth, with AssistiveTouch on (Accessibility → Touch → AssistiveTouch).")
                }

                Section {
                    if link.absolute == true {
                        Text("✅ Jumps straight to each point: no calibration needed")
                    } else {
                        Text(pointer.calibration)
                        Button("Calibrate pointer") { pointer.startCalibration() }.disabled(!link.ready || pointer.calibrating)
                    }
                } header: { Text("2 · Pointer") } footer: {
                    Text(link.absolute == true
                         ? "The device uses an absolute pointer (new firmware)."
                         : "Old firmware: the device clicks 3 spots and the app measures where they land (about 10 s).")
                }

                Section {
                    LabeledContent("Screen sharing", value: capture.state)
                    Button("Start (the device presses the button)") { Task { await pointer.startSharing() } }
                        .disabled(!link.ready || !pointer.calibrated || capture.running)
                    Button("Stop", role: .destructive) { capture.stop() }.disabled(!capture.running)
                } header: { Text("3 · Eyes") } footer: {
                    Text("Sharing stays on between tasks. Locking the phone turns it off; the next task turns it on again by itself.")
                }

                Section {
                    if routines.all.isEmpty {
                        Text("None yet. Each screen task the AI finishes is learned here.")
                    }
                    ForEach(routines.all.sorted { $0.learned > $1.learned }) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                            Text("\(r.steps.count) step\(r.steps.count == 1 ? "" : "s") · replayed \(r.replays)× without AI")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Forget", role: .destructive) { routines.delete(r.name) } }
                    }
                    if !routines.all.isEmpty {
                        Button("Forget all", role: .destructive) { routines.deleteAll() }
                    }
                } header: { Text("Learned routines") } footer: {
                    Text("Done once by the AI, then replayed by reading the screen only. Swipe left to forget one that went wrong.")
                }

                Section("Brains") {
                    LabeledContent("Fast brain (Luna Decisions)", value: Keys.fastBrainRoute)
                    LabeledContent("Big brain (Gemini 3.5 Flash-Lite)", value: Keys.gemini.isEmpty ? "missing key" : "Google AI Studio")
                }
            }
            .navigationTitle("Device")
            .fullScreenCover(isPresented: $pointer.calibrating) { CalibrationCatcher() }
        }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var link: DeviceLink

    var body: some View {
        NavigationStack {
            List(link.log) { line in
                VStack(alignment: .leading) {
                    Text(line.time, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
                    Text(line.text).font(.caption.monospaced())
                }
            }
            .navigationTitle("Log")
        }
    }
}
