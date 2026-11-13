import MantizaKit
import SwiftUI

@main
struct MantizaApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
    @StateObject private var pointer = Pointer()
    @StateObject private var agent = Agent()
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var request = ""
    @State private var booting = true

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
            .onAppear {
                capture.link = link
                pointer.link = link
                pointer.capture = capture
                agent.link = link
                agent.capture = capture
                agent.pointer = pointer
                agent.approvals.setUp()
                Net.start()
                let old = Direct.removeOldClockAlarms()
                if old > 0 { link.note("Removed \(old) old Mantiza alarm\(old == 1 ? "" : "s") (alarms now go into the Clock app)") }
                link.onShare = { [weak pointer = pointer] in Task { _ = await pointer?.startSharing() } }
                link.onStop = { [weak agent = agent] in agent?.stop() }
                Task {
                    // The head blinks twice (BootView), then straight into the app.
                    try? await Task.sleep(for: .milliseconds(850))
                    withAnimation(.easeOut(duration: 0.2)) { booting = false }
                }
            }
            // The widget's buttons: mantiza://run?q=... runs that task, mantiza://new opens the Task tab.
            .onOpenURL { url in
                tab = 0
                if let prompt = Shared.prompt(from: url), !prompt.isEmpty {
                    request = prompt
                    if !agent.running { agent.start(prompt) }
                }
            }
            // Development builds: send waiting task reports to the debug inbox on the PC.
            .onChange(of: phase) { _, now in
                if now == .active { Task { await RunLog.shared.flush() } }
            }
        }
    }
}
