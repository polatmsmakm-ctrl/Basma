import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DoneStorage.registerCategories()
        return true
    }

    // Notification arrives while the app is open
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let req = notification.request
        let id = req.identifier
        let kindRaw = req.content.userInfo["kind"] as? String
        let isBuzz = id.hasPrefix("buzz-")
        let isMain = id.hasSuffix("-at")

        if let raw = kindRaw, let kind = ReminderKind(rawValue: raw), isBuzz || isMain {
            // Continuous vibration + big stop screen instead of a plain banner
            DispatchQueue.main.async { AlertController.shared.start(kind: kind) }
            completionHandler(isBuzz ? [.list] : [.banner, .list, .sound])
            return
        }
        completionHandler([.banner, .list, .sound])
    }

    // Buttons on the notification and taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let src = response.notification.request.content
        let kindRaw = src.userInfo["kind"] as? String

        switch response.actionIdentifier {
        case NotifID.done:
            if let kindRaw = kindRaw { DoneStorage.mark(kindRaw: kindRaw) }
            NotificationCenter.default.post(name: .basmaStopBuzz, object: nil)

        case NotifID.stop, UNNotificationDefaultActionIdentifier:
            if let kindRaw = kindRaw { DoneStorage.stopBuzz(kindRaw: kindRaw) }
            NotificationCenter.default.post(name: .basmaStopBuzz, object: nil)

        case NotifID.snooze:
            if let kindRaw = kindRaw { DoneStorage.stopBuzz(kindRaw: kindRaw) }
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
            NotificationCenter.default.post(name: .basmaStopBuzz, object: nil)

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
