import SwiftUI
import UserNotifications

@main
struct MantizaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onAppear {
                    app.reloadCalibration()
                    KeyStore.refreshRedaction()
                    Task { await Notifier.requestPermission() }
                }
                .onOpenURL { app.open($0) }
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
            Tab("Run", systemImage: "sparkles") { NavigationStack { RunView() } }
            Tab("Workflows", systemImage: "square.stack.3d.up") { NavigationStack { WorkflowsView() } }
            Tab("Device", systemImage: "cursorarrow.rays") { NavigationStack { DeviceView() } }
            Tab("Look", systemImage: "eye") { NavigationStack { EyesView() } }
            Tab("Settings", systemImage: "gearshape") { NavigationStack { SettingsView() } }
        }
    }
}

/// Receives the approval notification's buttons.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Notifier.setUp(delegate: self)
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Notifier.category else { return }
        let yes = response.actionIdentifier == Notifier.approveAction
        await MainActor.run { RunControl.answer(yes) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
