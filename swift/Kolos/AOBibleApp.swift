import SwiftUI
import UserNotifications

/// Уведомления видны и когда приложение открыто (иначе iOS их молча прячет)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct KolosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = ModuleStore()
    @StateObject private var marks = MarksStore()
    @StateObject private var plans = PlansStore()
    @StateObject private var panes = PanesStore()
    @StateObject private var sermons = SermonStore()
    @StateObject private var audio = AudioEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(marks)
                .environmentObject(plans)
                .environmentObject(panes)
                .environmentObject(sermons)
                .environmentObject(audio)
                // открыли приложение — звонящий будильник замолкает
                .onChange(of: phase) { _, p in
                    if p == .active { Reminders.stopRinging() }
                }
        }
    }
}
