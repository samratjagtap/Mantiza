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
        // Sharp, dark tab bar in Mantiza's colours.
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Theme.ink)
        bar.shadowColor = UIColor(Theme.line)
        let item = bar.stackedLayoutAppearance
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        item.normal.iconColor = UIColor(Theme.dim)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.dim), .font: font]
        item.selected.iconColor = UIColor(Theme.green)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.green), .font: font]
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView(selection: $tab) {
                    TaskView(request: $request).tag(0).tabItem { Label("TASK", systemImage: "square.grid.3x3.fill") }
                    DeviceView().tag(1).tabItem { Label("DEVICE", systemImage: "cursorarrow.rays") }
                    LogView().tag(2).tabItem { Label("LOG", systemImage: "text.alignleft") }
                }
                .tint(Theme.green)

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
                link.onShare = { [weak pointer = pointer] in Task { _ = await pointer?.startSharing() } }
                link.onStop = { [weak agent = agent] in agent?.stop() }
                Task {
                    try? await Task.sleep(for: .milliseconds(1400))
                    withAnimation(.easeOut(duration: 0.35)) { booting = false }
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
