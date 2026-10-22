import Foundation
import SwiftUI
import UserNotifications

enum ReminderKind: String, Codable, CaseIterable {
    case entry      // بصمة الدخول
    case presence   // بصمة التواجد
    case exit       // بصمة الخروج

    var title: String {
        switch self {
        case .entry: return "بصمة الدخول"
        case .presence: return "بصمة التواجد"
        case .exit: return "بصمة الخروج"
        }
    }

    var icon: String {
        switch self {
        case .entry: return "arrow.down.right.circle.fill"
        case .presence: return "person.fill.checkmark"
        case .exit: return "arrow.up.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .entry: return .green
        case .presence: return .orange
        case .exit: return .red
        }
    }
}

struct FingerprintReminder: Identifiable, Codable {
    var id: String { kind.rawValue }
    var kind: ReminderKind
    var enabled: Bool
    var hour: Int
    var minute: Int
    var days: Set<Int>        // 1 = الأحد ... 7 = السبت
    var leadMinutes: Int      // تنبيه مسبق قبل الموعد

    var timeDate: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = c.hour ?? hour
            minute = c.minute ?? minute
        }
    }
}

let weekdayNames: [(Int, String)] = [
    (1, "الأحد"), (2, "الاثنين"), (3, "الثلاثاء"), (4, "الأربعاء"),
    (5, "الخميس"), (6, "الجمعة"), (7, "السبت")
]

final class ReminderStore: ObservableObject {
    @Published var reminders: [FingerprintReminder] {
        didSet { save(); schedule() }
    }
    @Published var doneKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(doneKeys), forKey: "basma.done") }
    }
    @Published var permissionDenied = false

    private let key = "basma.reminders.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([FingerprintReminder].self, from: data) {
            reminders = saved
        } else {
            let work: Set<Int> = [1, 2, 3, 4, 5]   // الأحد - الخميس
            reminders = [
                FingerprintReminder(kind: .entry, enabled: true, hour: 7, minute: 0, days: work, leadMinutes: 5),
                FingerprintReminder(kind: .presence, enabled: true, hour: 10, minute: 0, days: work, leadMinutes: 0),
                FingerprintReminder(kind: .exit, enabled: true, hour: 13, minute: 30, days: work, leadMinutes: 5)
            ]
        }
        doneKeys = Set(UserDefaults.standard.stringArray(forKey: "basma.done") ?? [])
        requestPermission()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.permissionDenied = !granted
                if granted { self.schedule() }
            }
        }
    }

    // MARK: - Today's checklist

    private func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func isDoneToday(_ kind: ReminderKind) -> Bool {
        doneKeys.contains("\(todayString())|\(kind.rawValue)")
    }

    func toggleDone(_ kind: ReminderKind) {
        let k = "\(todayString())|\(kind.rawValue)"
        if doneKeys.contains(k) { doneKeys.remove(k) } else { doneKeys.insert(k) }
    }

    var todayKinds: [FingerprintReminder] {
        let wd = Calendar.current.component(.weekday, from: Date())
        return reminders.filter { $0.enabled && $0.days.contains(wd) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - Scheduling

    func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for r in reminders where r.enabled {
            for day in r.days {
                // exact time
                add(center, id: "\(r.kind.rawValue)-\(day)-at",
                    title: r.kind.title,
                    body: "حان وقت \(r.kind.title) الآن ✋",
                    weekday: day, hour: r.hour, minute: r.minute)

                // early heads-up
                if r.leadMinutes > 0 {
                    let total = (day - 1) * 1440 + r.hour * 60 + r.minute - r.leadMinutes
                    let wrapped = ((total % 10080) + 10080) % 10080
                    let wd = wrapped / 1440 + 1
                    let rem = wrapped % 1440
                    add(center, id: "\(r.kind.rawValue)-\(day)-lead",
                        title: r.kind.title,
                        body: "بعد \(r.leadMinutes) دقائق موعد \(r.kind.title)",
                        weekday: wd, hour: rem / 60, minute: rem % 60)
                }
            }
        }
    }

    private func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String,
                     weekday: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "بصمتي"
        content.body = "هكذا سيظهر التذكير ✋"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }
}
