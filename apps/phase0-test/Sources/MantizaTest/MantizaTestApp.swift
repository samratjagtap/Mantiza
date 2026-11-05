import SwiftUI

@main
struct MantizaTestApp: App {
    @StateObject private var link = DeviceLink()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
        }
        .onChange(of: scenePhase) { _, phase in
            link.note("App is now \(phase == .active ? "in front" : phase == .background ? "in the background" : "inactive")")
        }
    }
}
