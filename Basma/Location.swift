import Foundation
import CoreLocation
import UserNotifications

/// Workplace geofence: reminds you to fingerprint when you arrive and when you leave.
final class WorkLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WorkLocation()

    @Published var authStatus: CLAuthorizationStatus
    @Published var hasWorkplace: Bool
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { ensureAlways() }
            refreshMonitoring()
        }
    }
    @Published var radius: Double {
        didSet {
            UserDefaults.standard.set(radius, forKey: Keys.radius)
            refreshMonitoring()
        }
    }
    @Published var message: String?

    private enum Keys {
        static let lat = "basma.work.lat"
        static let lon = "basma.work.lon"
        static let radius = "basma.work.radius"
        static let enabled = "basma.work.enabled"
        static let notified = "basma.geoNotified"
    }

    private let manager = CLLocationManager()
    private let regionID = "basma.work"
    private var wantsSave = false

    override init() {
        authStatus = CLLocationManager().authorizationStatus
        let d = UserDefaults.standard
        hasWorkplace = d.object(forKey: Keys.lat) != nil && d.object(forKey: Keys.lon) != nil
        enabled = d.bool(forKey: Keys.enabled)
        let r = d.double(forKey: Keys.radius)
        radius = r > 0 ? r : 150
        super.init()
        manager.delegate = self
    }

    /// Call at launch so region events (which can relaunch the app) reach the delegate.
    func start() {
        manager.delegate = self
        authStatus = manager.authorizationStatus
        refreshMonitoring()
    }

    // MARK: - Setting the workplace

    func saveCurrentAsWorkplace() {
        message = nil
        wantsSave = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsSave = false
            message = "اسمح للتطبيق بالموقع من إعدادات الآيفون."
        default:
            manager.requestLocation()
        }
    }

    func clearWorkplace() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Keys.lat)
        d.removeObject(forKey: Keys.lon)
        hasWorkplace = false
        enabled = false
    }

    private func ensureAlways() {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if s == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Monitoring

    private func refreshMonitoring() {
        for region in manager.monitoredRegions where region.identifier == regionID {
            manager.stopMonitoring(for: region)
        }
        let d = UserDefaults.standard
        guard enabled, d.object(forKey: Keys.lat) != nil,
              manager.authorizationStatus == .authorizedAlways else { return }

        let center = CLLocationCoordinate2D(latitude: d.double(forKey: Keys.lat),
                                            longitude: d.double(forKey: Keys.lon))
        let region = CLCircularRegion(center: center, radius: max(100, radius), identifier: regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authStatus = manager.authorizationStatus
            if self.wantsSave,
               manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
            if self.enabled && manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            self.refreshMonitoring()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsSave, let loc = locations.last else { return }
        wantsSave = false
        let d = UserDefaults.standard
        d.set(loc.coordinate.latitude, forKey: Keys.lat)
        d.set(loc.coordinate.longitude, forKey: Keys.lon)
        DispatchQueue.main.async {
            self.hasWorkplace = true
            self.message = "تم حفظ موقع الدوام ✓"
            self.enabled = true          // didSet asks for "Always" and starts monitoring
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        wantsSave = false
        DispatchQueue.main.async {
            self.message = "تعذّر تحديد موقعك. جرّب مرة ثانية وأنت في مكان مفتوح."
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionID else { return }
        notify(kind: .entry, arriving: true)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionID else { return }
        notify(kind: .exit, arriving: false)
    }

    // MARK: - Notifying

    private func notify(kind: ReminderKind, arriving: Bool) {
        let cal = Calendar.current
        let now = Date()
        let d = UserDefaults.standard

        guard let data = d.data(forKey: "basma.reminders.v1"),
              let reminders = try? JSONDecoder().decode([FingerprintReminder].self, from: data),
              let r = reminders.first(where: { $0.kind == kind }), r.enabled else { return }

        let wd = cal.component(.weekday, from: now)
        guard r.days.contains(wd) else { return }

        let day = DoneStorage.dayString(now)
        let vacation = Set(d.stringArray(forKey: "basma.vacationDays") ?? [])
        if vacation.contains(day) { return }
        if DoneStorage.load().contains("\(day)|\(kind.rawValue)") { return }

        // Leaving for a short errand long before closing time shouldn't nag.
        if kind == .exit,
           let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: now),
           now < fire.addingTimeInterval(-45 * 60) { return }

        // Once per day per kind
        let oldest = DoneStorage.dayString(now.addingTimeInterval(-3 * 86400))
        var notified = Set(d.stringArray(forKey: Keys.notified) ?? []).filter { String($0.prefix(10)) >= oldest }
        let key = "\(day)|\(kind.rawValue)|geo"
        if notified.contains(key) { return }
        notified.insert(key)
        d.set(Array(notified), forKey: Keys.notified)

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = arriving ? "وصلت للدوام ✋ لا تنسَ \(kind.title)" : "غادرت الدوام ✋ لا تنسَ \(kind.title)"
        content.sound = AlarmSound.current.notificationSound
        content.categoryIdentifier = NotifID.category
        content.userInfo = ["kind": kind.rawValue]
        content.threadIdentifier = "basma-\(kind.rawValue)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "geo-\(kind.rawValue)-\(day)", content: content, trigger: trigger)
        )
    }
}
