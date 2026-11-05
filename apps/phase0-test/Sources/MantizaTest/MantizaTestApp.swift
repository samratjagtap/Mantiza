import SwiftUI

@main
struct MantizaTestApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
    @StateObject private var share = ShareByDevice()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("T2 Device", systemImage: "dot.radiowaves.left.and.right") }
                CaptureView()
                    .tabItem { Label("T3/T4 Screen", systemImage: "rectangle.dashed.badge.record") }
                LogView()
                    .tabItem { Label("Log", systemImage: "list.bullet") }
            }
            .environmentObject(link)
            .environmentObject(capture)
            .environmentObject(share)
            .onAppear {
                capture.link = link
                share.link = link
                share.capture = capture
                link.onShare = { [weak share = share] in share?.share(fromDevice: true) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            link.note("App is now \(phase == .active ? "in front" : phase == .background ? "in the background" : "inactive")")
        }
    }
}
