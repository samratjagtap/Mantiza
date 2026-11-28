import MantizaKit
import SwiftUI

@main
struct MantizaApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
    @StateObject private var pointer = Pointer()
    @StateObject private var agent = Agent()
    @StateObject private var listener = Listener()
    @ObservedObject private var inbox = Inbox.shared
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var request = ""
    @State private var booting = true
    @State private var later: [String] = []   // scheduled tasks tapped while another task ran

    init() {
        // A quiet dark tab bar: grey items, the selected one white.
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Theme.ink)
        bar.shadowColor = UIColor(Theme.line)
        let item = bar.stackedLayoutAppearance
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        item.normal.iconColor = UIColor(Theme.dim)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.dim), .font: font]
        item.selected.iconColor = UIColor(Theme.text)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.text), .font: font]
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
        // Before any screen: a notification tap that launched the app must not be missed.
        NotificationRouter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView(selection: $tab) {
                    TaskView(request: $request).tag(0).tabItem { Label("Task", systemImage: "sparkles") }
                    DeviceView().tag(1).tabItem { Label("Device", systemImage: "dot.radiowaves.left.and.right") }
                    LogView().tag(2).tabItem { Label("Log", systemImage: "list.bullet") }
                }
                .tint(Theme.text)

                if booting {
                    BootView().transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .environmentObject(link)
            .environmentObject(capture)
            .environmentObject(pointer)
            .environmentObject(agent)
            .environmentObject(agent.approvals)
            .environmentObject(agent.routines)
            .environmentObject(agent.chats)
            .environmentObject(listener)
            .environmentObject(Voice.shared)
            .onAppear {
                capture.link = link
                pointer.link = link
                pointer.capture = capture
                agent.link = link
                agent.capture = capture
                agent.pointer = pointer
                agent.approvals.setUp()
                // A schedule's notification was tapped: run it now, or right after the task running now.
                Schedules.shared.start { prompt in
                    tab = 0
                    if agent.running { later.append(prompt) } else { agent.start(prompt) }
                }
                Net.start()
                let old = Direct.removeOldClockAlarms()
                if old > 0 { link.note("Removed \(old) old Mantiza alarm\(old == 1 ? "" : "s") (alarms now go into the Clock app)") }
                link.onShare = { [weak pointer = pointer] in Task { _ = await pointer?.startSharing() } }
                link.onStop = { [weak agent = agent] in agent?.stop() }
                // What was said becomes the request and runs at once; its result is spoken.
                listener.onDone = { text in
                    if !agent.running { agent.start(text, byVoice: true) }
                }
                handle(inbox.take())  // Siri or a button started the app with something to do
                Task {
                    // The head blinks twice (BootView), then straight into the app.
                    try? await Task.sleep(for: .milliseconds(850))
                    withAnimation(.easeOut(duration: 0.2)) { booting = false }
                }
            }
            // Links from the widget, the Lock Screen and the Live Activity: mantiza://run?q=... runs
            // that task, mantiza://listen opens listening, mantiza://stop stops, mantiza://new opens
            // the Task tab.
            .onOpenURL { url in
                tab = 0
                if let prompt = Shared.prompt(from: url), !prompt.isEmpty {
                    if !agent.running { agent.start(prompt) }
                } else if url == Shared.listenURL {
                    handle(.listen)
                } else if url == Shared.stopURL {
                    handle(.stop)
                }
            }
            // Siri ("Ask Mantiza"), the Control Centre button and the Live Activity's Stop button.
            .onChange(of: inbox.count) { _, _ in handle(inbox.take()) }
            .onChange(of: agent.running) { _, running in
                if !running, !later.isEmpty { agent.start(later.removeFirst()) }
            }
            // Development builds: send waiting task reports to the debug inbox on the PC.
            .onChange(of: phase) { _, now in
                if now == .active { Task { await RunLog.shared.flush() } }
            }
        }
    }

    private func handle(_ command: Command?) {
        guard let command else { return }
        switch command {
        case .run(let prompt):
            let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            tab = 0
            if !agent.running { agent.start(text, byVoice: true) }  // it came through Siri: answer out loud
        case .listen:
            tab = 0
            if !agent.running, !listener.listening { Task { await listener.start() } }
        case .stop:
            listener.finish(run: false)
            Voice.shared.stopSpeaking()
            if agent.running { agent.stop() }
        }
    }
}
