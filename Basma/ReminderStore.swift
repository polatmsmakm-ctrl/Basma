import Foundation
import SwiftUI
import UserNotifications

// MARK: - Models

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

struct DayStat: Identifiable {
    let date: Date
    let planned: Int
    let done: Int
    var id: TimeInterval { date.timeIntervalSince1970 }
    var fraction: Double { planned == 0 ? 0 : Double(done) / Double(planned) }
}

let weekdayNames: [(Int, String)] = [
    (1, "الأحد"), (2, "الاثنين"), (3, "الثلاثاء"), (4, "الأربعاء"),
    (5, "الخميس"), (6, "الجمعة"), (7, "السبت")
]

// MARK: - Notification constants

enum NotifID {
    static let category = "BASMA_REMINDER"
    static let done = "BASMA_DONE"
    static let snooze = "BASMA_SNOOZE"
    static let snoozePrefix = "snooze-"
}

extension Notification.Name {
    static let basmaDoneChanged = Notification.Name("basmaDoneChanged")
}

// MARK: - Done storage (shared by the app and notification actions)

enum DoneStorage {
    static let key = "basma.done"

    static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// Called from the notification "done" button (may run in the background).
    static func mark(kindRaw: String) {
        var s = load()
        s.insert("\(dayString())|\(kindRaw)")
        save(s)
        cleanFollowups(kindRaw: kindRaw)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .basmaDoneChanged, object: nil)
        }
    }

    /// Removes delivered banners and pending snoozes of this kind.
    static func cleanFollowups(kindRaw: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { list in
            let ids = list
                .filter { ($0.request.content.userInfo["kind"] as? String) == kindRaw }
                .map { $0.request.identifier }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
        center.getPendingNotificationRequests { list in
            let ids = list
                .filter { $0.identifier.hasPrefix(NotifID.snoozePrefix)
                    && ($0.content.userInfo["kind"] as? String) == kindRaw }
                .map { $0.identifier }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: NotifID.done, title: "تمت البصمة ✓", options: [])
        let snooze = UNNotificationAction(identifier: NotifID.snooze, title: "ذكّرني بعد ١٠ دقائق", options: [])
        let cat = UNNotificationCategory(identifier: NotifID.category,
                                         actions: [done, snooze],
                                         intentIdentifiers: [],
                                         options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }
}

// MARK: - Store

final class ReminderStore: ObservableObject {
    @Published var reminders: [FingerprintReminder] {
        didSet { save(); schedule() }
    }
    @Published var doneKeys: Set<String> {
        didSet { DoneStorage.save(doneKeys) }
    }
    /// First day reminders are active again (start of day). nil = no vacation.
    @Published var resumeDate: Date? {
        didSet { saveResume(); schedule() }
    }
    @Published var permissionDenied = false

    /// yyyy-MM-dd strings of vacation days (kept so streak/stats skip them).
    var vacationDays: Set<String> {
        didSet { UserDefaults.standard.set(Array(vacationDays), forKey: vacationKey) }
    }

    private let key = "basma.reminders.v1"
    private let resumeKey = "basma.resumeDate"
    private let vacationKey = "basma.vacationDays"

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
        doneKeys = DoneStorage.load()
        let t = UserDefaults.standard.double(forKey: resumeKey)
        resumeDate = t > 0 ? Date(timeIntervalSince1970: t) : nil
        vacationDays = Set(UserDefaults.standard.stringArray(forKey: vacationKey) ?? [])

        NotificationCenter.default.addObserver(forName: .basmaDoneChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reloadDone()
        }
        requestPermission()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func saveResume() {
        if let d = resumeDate {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: resumeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: resumeKey)
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

    /// Called whenever the app becomes active.
    func refresh() {
        reloadDone()
        if let r = resumeDate, r <= Date() {
            resumeDate = nil          // vacation is over (didSet reschedules)
        } else {
            schedule()
        }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                self.permissionDenied = (s.authorizationStatus == .denied)
            }
        }
    }

    private func reloadDone() {
        let fresh = DoneStorage.load()
        if fresh != doneKeys { doneKeys = fresh }
    }

    // MARK: - Today's checklist

    func isDone(_ kind: ReminderKind, on date: Date) -> Bool {
        doneKeys.contains("\(DoneStorage.dayString(date))|\(kind.rawValue)")
    }

    func isDoneToday(_ kind: ReminderKind) -> Bool {
        isDone(kind, on: Date())
    }

    func toggleDone(_ kind: ReminderKind) {
        let k = "\(DoneStorage.dayString())|\(kind.rawValue)"
        if doneKeys.contains(k) {
            doneKeys.remove(k)
        } else {
            doneKeys.insert(k)
            DoneStorage.cleanFollowups(kindRaw: kind.rawValue)
        }
    }

    func isVacationDay(_ date: Date) -> Bool {
        vacationDays.contains(DoneStorage.dayString(date))
    }

    var isOnVacation: Bool {
        if let r = resumeDate { return r > Date() }
        return false
    }

    func scheduledKinds(on date: Date) -> [ReminderKind] {
        if isVacationDay(date) { return [] }
        let wd = Calendar.current.component(.weekday, from: date)
        return reminders.filter { $0.enabled && $0.days.contains(wd) }.map { $0.kind }
    }

    var todayKinds: [FingerprintReminder] {
        let now = Date()
        if isVacationDay(now) { return [] }
        let wd = Calendar.current.component(.weekday, from: now)
        return reminders.filter { $0.enabled && $0.days.contains(wd) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - Vacation

    func startVacation(lastDay: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let last = cal.startOfDay(for: lastDay)
        guard last >= today else { return }
        let resume = cal.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86400)

        var set = vacationDays
        var d = today
        while d <= last {
            set.insert(DoneStorage.dayString(d))
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
        vacationDays = set
        resumeDate = resume
    }

    func endVacation() {
        let todayStr = DoneStorage.dayString()
        vacationDays = vacationDays.filter { $0 < todayStr }
        resumeDate = nil
    }

    // MARK: - Stats

    func weekStats() -> [DayStat] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { off -> DayStat? in
            guard let day = cal.date(byAdding: .day, value: -off, to: Date()) else { return nil }
            let kinds = scheduledKinds(on: day)
            let done = kinds.filter { isDone($0, on: day) }.count
            return DayStat(date: day, planned: kinds.count, done: done)
        }
    }

    /// Consecutive days where every scheduled fingerprint was done.
    var streak: Int {
        let cal = Calendar.current
        let earliest = doneKeys
            .compactMap { $0.split(separator: "|").first.map(String.init) }
            .min()
        guard let earliest = earliest else { return 0 }

        var count = 0
        for offset in 0..<400 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            if DoneStorage.dayString(day) < earliest { break }
            let planned = scheduledKinds(on: day)
            if planned.isEmpty { continue }
            let allDone = planned.allSatisfy { isDone($0, on: day) }
            if allDone {
                count += 1
            } else if offset == 0 {
                continue            // today is still in progress
            } else {
                break
            }
        }
        return count
    }

    // MARK: - Scheduling

    func schedule() {
        let requests = buildRequests()
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }
                .filter { !$0.hasPrefix(NotifID.snoozePrefix) && $0 != "test" }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for r in requests { center.add(r) }
        }
    }

    private func makeRequest(id: String, kind: ReminderKind, body: String,
                             comps: DateComponents, repeats: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotifID.category
        content.userInfo = ["kind": kind.rawValue]
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func buildRequests() -> [UNNotificationRequest] {
        let cal = Calendar.current
        let now = Date()

        // Vacation: one-off notifications starting from the resume day.
        if let resume = resumeDate, resume > now {
            var items: [(Date, UNNotificationRequest)] = []
            let startOfToday = cal.startOfDay(for: now)
            for offset in 0..<75 {
                guard let day = cal.date(byAdding: .day, value: offset, to: startOfToday), day >= resume else { continue }
                let wd = cal.component(.weekday, from: day)
                for r in reminders where r.enabled && r.days.contains(wd) {
                    guard let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day) else { continue }
                    let stamp = Int(fire.timeIntervalSince1970)
                    if fire > now {
                        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                        items.append((fire, makeRequest(id: "\(r.kind.rawValue)-\(stamp)-at", kind: r.kind,
                                                        body: "حان وقت \(r.kind.title) الآن ✋",
                                                        comps: c, repeats: false)))
                    }
                    if r.leadMinutes > 0 {
                        let lead = fire.addingTimeInterval(-Double(r.leadMinutes * 60))
                        if lead > now {
                            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: lead)
                            items.append((lead, makeRequest(id: "\(r.kind.rawValue)-\(stamp)-lead", kind: r.kind,
                                                            body: "بعد \(r.leadMinutes) دقائق موعد \(r.kind.title)",
                                                            comps: c, repeats: false)))
                        }
                    }
                }
            }
            items.sort { $0.0 < $1.0 }
            return items.prefix(55).map { $0.1 }
        }

        // Normal: weekly repeating notifications.
        var out: [UNNotificationRequest] = []
        for r in reminders where r.enabled {
            for day in r.days {
                var c = DateComponents()
                c.weekday = day
                c.hour = r.hour
                c.minute = r.minute
                out.append(makeRequest(id: "\(r.kind.rawValue)-\(day)-at", kind: r.kind,
                                       body: "حان وقت \(r.kind.title) الآن ✋",
                                       comps: c, repeats: true))

                if r.leadMinutes > 0 {
                    let total = (day - 1) * 1440 + r.hour * 60 + r.minute - r.leadMinutes
                    let wrapped = ((total % 10080) + 10080) % 10080
                    var lc = DateComponents()
                    lc.weekday = wrapped / 1440 + 1
                    lc.hour = (wrapped % 1440) / 60
                    lc.minute = wrapped % 60
                    out.append(makeRequest(id: "\(r.kind.rawValue)-\(day)-lead", kind: r.kind,
                                           body: "بعد \(r.leadMinutes) دقائق موعد \(r.kind.title)",
                                           comps: lc, repeats: true))
                }
            }
        }
        return out
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "بصمتي"
        content.body = "هكذا سيظهر التذكير ✋ اسحب الإشعار لتظهر الأزرار"
        content.sound = .default
        content.categoryIdentifier = NotifID.category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }
}
