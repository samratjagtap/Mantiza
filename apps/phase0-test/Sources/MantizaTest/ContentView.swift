import SwiftUI

struct ContentView: View {
    @EnvironmentObject var link: DeviceLink
    @State private var typed = ""
    @FocusState private var boxFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Bluetooth", value: link.bluetooth)
                    LabeledContent("Device", value: link.status)
                    LabeledContent("Found by", value: link.foundBy)
                    Button("Connect again") { link.findDevice() }
                }

                Section {
                    Button("Ping ×10") { link.pingTen() }
                        .disabled(!link.ready)
                    Text(link.pingResult).font(.callout.monospacedDigit())
                } header: {
                    Text("T2a · Round trip")
                } footer: {
                    Text("App → device → app. Shows how fast commands get through.")
                }

                Section {
                    Button("Move pointer in a square") { link.moveSquare() }
                        .disabled(!link.ready)
                    TextField("Tap here, then press Type", text: $typed)
                        .focused($boxFocused)
                    Button("Type \"Hello from the app\"") { link.send("t Hello from the app") }
                        .disabled(!link.ready)
                } header: {
                    Text("T2b · App drives the mouse and keyboard")
                } footer: {
                    Text("The app sends a command, the device moves the pointer or types, like a real Mantiza task.")
                }

                Section {
                    LabeledContent("Asks answered", value: "\(link.asksAnswered)")
                    LabeledContent("…while in background", value: "\(link.asksInBackground)")
                } header: {
                    Text("T2c · Device asks, app answers")
                } footer: {
                    Text("On the StickS3 pick \"2 Auto ask 5s\" and press the front button. Then leave this app for 5 minutes. The device counts the answers (A answered/sent).")
                }

                Section {
                    Button(link.beating ? "Stop heartbeat" : "Start heartbeat (every 5 s)") { link.toggleBeat() }
                        .disabled(!link.ready)
                    LabeledContent("Beats sent", value: "\(link.beatsSent)")
                } header: {
                    Text("T2d · App sends on its own")
                } footer: {
                    Text("Start, then leave this app. The device's B number shows whether the app keeps sending from the background.")
                }

            }
            .navigationTitle("Mantiza T2")
        }
    }
}
