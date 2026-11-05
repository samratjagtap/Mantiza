import SwiftUI

@main
struct MantizaTestApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
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
            .onAppear { capture.link = link }
        }
        .onChange(of: scenePhase) { _, phase in
            link.note("App is now \(phase == .active ? "in front" : phase == .background ? "in the background" : "inactive")")
        }
    }
}
