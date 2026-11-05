import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var capture: ScreenCapture

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("State", value: capture.state)
                    LabeledContent("Running for", value: capture.runningFor)
                    LabeledContent("Frames", value: "\(capture.frames)")
                    LabeledContent("…while app in background", value: "\(capture.backgroundFrames)")
                    LabeledContent("Last frame", value: capture.lastFrameAgo)
                    LabeledContent("Longest gap", value: capture.longestGap)
                } header: {
                    Text("T3 · Capture")
                } footer: {
                    Text("Start, choose to share the screen, then use other apps for 5+ minutes. Then lock the phone for 1 minute. Come back and check the numbers and the thumbnails below. Frames only arrive when something on screen changes, so a still screen gives gaps.")
                }

                Section {
                    Button("Start (picker)") { capture.startWithPicker() }
                    Button("Stop", role: .destructive) { capture.stop() }
                        .disabled(!capture.running)
                    Button("Restart without picker") { capture.restartWithoutPicker() }
                        .disabled(!capture.hasSavedChoice)
                    LabeledContent("Pickers shown", value: "\(capture.pickersShown)")
                    LabeledContent("Captures started", value: "\(capture.starts)")
                } header: {
                    Text("T4 · Does it ask every time?")
                } footer: {
                    Text("Start → Stop → Restart without picker. If capture starts again without asking, the session can be reused. Also try Start (picker) a second time: does iOS ask again?")
                }

                Section {
                    if capture.thumbs.isEmpty {
                        Text("A thumbnail is saved every 20 s while capturing.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Clear thumbnails", role: .destructive) { capture.clearThumbs() }
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(capture.thumbs) { t in
                                    VStack(spacing: 4) {
                                        Image(uiImage: t.image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 180)
                                            .border(t.background ? Color.orange : Color.green, width: 2)
                                        Text(t.time, format: .dateTime.hour().minute().second())
                                            .font(.caption2.monospacedDigit())
                                        Text(t.background ? "background" : "in front")
                                            .font(.caption2)
                                            .foregroundStyle(t.background ? .orange : .green)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("What was captured")
                }
            }
            .navigationTitle("Mantiza T3/T4")
        }
    }
}

struct LogView: View {
    @EnvironmentObject var link: DeviceLink

    var body: some View {
        NavigationStack {
            List {
                Button("Clear log and counts", role: .destructive) { link.resetCounts() }
                ForEach(link.log) { line in
                    HStack(alignment: .top) {
                        Text(line.time, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Text(line.text)
                    }
                    .font(.caption.monospaced())
                }
            }
            .navigationTitle("Log")
        }
    }
}
