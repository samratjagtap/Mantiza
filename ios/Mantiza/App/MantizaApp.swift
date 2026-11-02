import SwiftUI

@main
struct MantizaApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onAppear { app.reloadCalibration() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.onboarded {
            MainTabs()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Device", systemImage: "cursorarrow.rays") { NavigationStack { DeviceView() } }
            Tab("Look", systemImage: "eye") { NavigationStack { EyesView() } }
        }
    }
}
