import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DoneStorage.registerCategories()
        return true
    }

    // Show the banner even when the app is open
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // Buttons on the notification: "done" and "snooze 10 minutes"
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let src = response.notification.request.content
        let kindRaw = src.userInfo["kind"] as? String

        switch response.actionIdentifier {
        case NotifID.done:
            if let kindRaw = kindRaw { DoneStorage.mark(kindRaw: kindRaw) }

        case NotifID.snooze:
            let c = UNMutableNotificationContent()
            c.title = src.title
            c.body = "لم تبصم بعد؟ \(src.title) ✋"
            c.sound = .default
            c.categoryIdentifier = NotifID.category
            c.userInfo = src.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
            let req = UNNotificationRequest(identifier: NotifID.snoozePrefix + UUID().uuidString,
                                            content: c, trigger: trigger)
            center.add(req)

        default:
            break
        }
        completionHandler()
    }
}

@main
struct BasmaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ReminderStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.refresh() }
                }
        }
    }
}
