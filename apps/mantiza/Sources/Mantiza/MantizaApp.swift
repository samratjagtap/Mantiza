import SwiftUI

@main
struct MantizaApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
    @StateObject private var pointer = Pointer()
    @StateObject private var agent = Agent()

    var body: some Scene {
        WindowGroup {
            TabView {
                TaskView().tabItem { Label("Task", systemImage: "sparkles") }
                DeviceView().tabItem { Label("Device", systemImage: "cursorarrow.click.2") }
                LogView().tabItem { Label("Log", systemImage: "list.bullet") }
            }
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
                // The device's menu item "4 Share screen" opens this app and sends "share".
                link.onShare = { [weak pointer = pointer] in Task { _ = await pointer?.startSharing() } }
                link.onStop = { [weak agent = agent] in agent?.stop() }
            }
        }
    }
}
