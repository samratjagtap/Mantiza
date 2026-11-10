import SwiftUI

@main
struct MantizaTestApp: App {
    @StateObject private var link = DeviceLink()
    @StateObject private var capture = ScreenCapture()
    @StateObject private var share = ShareByDevice()
    @StateObject private var battery = BatteryTest()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("T2 Device", systemImage: "dot.radiowaves.left.and.right") }
                CaptureView()
                    .tabItem { Label("T3/T4 Screen", systemImage: "rectangle.dashed.badge.record") }
                BatteryView()
                    .tabItem { Label("T9 Battery", systemImage: "battery.75percent") }
                LogView()
                    .tabItem { Label("Log", systemImage: "list.bullet") }
            }
            .environmentObject(link)
            .environmentObject(capture)
            .environmentObject(share)
            .environmentObject(battery)
            .onAppear {
                capture.link = link
                share.link = link
                share.capture = capture
                battery.capture = capture
                link.onBattery = { [weak battery = battery] parts in battery?.got(parts) }
                link.onShare = { [weak share = share] in share?.share(fromDevice: true) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            link.note("App is now \(phase == .active ? "in front" : phase == .background ? "in the background" : "inactive")")
        }
    }
}
