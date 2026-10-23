import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Notification constants

enum NotifID {
    static let category = "BASMA_REMINDER"
    static let done = "BASMA_DONE"
    static let snooze = "BASMA_SNOOZE"
    static let stop = "BASMA_STOP"
    static let snoozePrefix = "snooze-"
}

extension Notification.Name {
    static let basmaDoneChanged = Notification.Name("basmaDoneChanged")
}

// MARK: - Done storage (shared by the app and notification actions)

enum DoneStorage {
    static let key = "basma.done"

    static func dayString(_ date: Date = Date()) -> String {
        SharedStore.dayString(date)
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
    // MARK: vibration pulses

    private static let mutedKey = "basma.buzzMuted"

    static func suppressedBuzz() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? [])
    }

    /// Stops the pulse chain of this alarm for today (pending + delivered) and keeps it stopped.
    static func stopBuzz(kindRaw: String) {
        let day = dayString()
        let oldest = dayString(Date().addingTimeInterval(-3 * 86400))
        var s = suppressedBuzz().filter { String($0.prefix(10)) >= oldest }
        s.insert("\(day)|\(kindRaw)")
        UserDefaults.standard.set(Array(s), forKey: mutedKey)

        let center = UNUserNotificationCenter.current()
        let prefix = "buzz-\(kindRaw)-\(day)-"
        center.getPendingNotificationRequests { list in
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
        center.getDeliveredNotifications { list in
            let ids = list
                .filter { $0.request.identifier.hasPrefix("buzz-")
                    && ($0.request.content.userInfo["kind"] as? String) == kindRaw }
                .map { $0.request.identifier }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    static func cleanFollowups(kindRaw: String) {
        stopBuzz(kindRaw: kindRaw)
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { list in
            let ids = list
                .filter { ($0.request.content.userInfo["kind"] as? String) == kindRaw }
                .map { $0.request.identifier }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
        let nagID = "nag-\(kindRaw)-\(dayString())"
        center.getPendingNotificationRequests { list in
            let ids = list
                .filter { ($0.identifier.hasPrefix(NotifID.snoozePrefix)
                           && ($0.content.userInfo["kind"] as? String) == kindRaw)
                          || $0.identifier == nagID }
                .map { $0.identifier }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: NotifID.done, title: "تمت البصمة ✓", options: [])
        let stop = UNNotificationAction(identifier: NotifID.stop, title: "إيقاف الاهتزاز", options: [])
        let snooze = UNNotificationAction(identifier: NotifID.snooze, title: "ذكّرني بعد ١٠ دقائق", options: [])
        let cat = UNNotificationCategory(identifier: NotifID.category,
                                         actions: [done, stop, snooze],
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
        didSet { DoneStorage.save(doneKeys); schedule() }
    }
    /// Minutes after the exact time to nag again if the fingerprint isn't marked done (0 = off).
    @Published var nagMinutes: Int {
        didSet { UserDefaults.standard.set(nagMinutes, forKey: nagKey); schedule() }
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
    private let nagKey = "basma.nagMinutes"
    /// Real system alarm (AlarmKit, iOS 26+): rings and vibrates until you stop it, even when silent.
    @Published var systemAlarmEnabled: Bool {
        didSet {
            UserDefaults.standard.set(systemAlarmEnabled, forKey: "basma.sysAlarm")
            syncSystemAlarms(force: true)
        }
    }
    /// The sound used for reminders, the alert screen and the system alarm.
    @Published var alarmSound: AlarmSound {
        didSet {
            UserDefaults.standard.set(alarmSound.rawValue, forKey: "basma.sound")
            syncSystemAlarms(force: true)
            schedule()
        }
    }
    @Published var systemAlarmActive = false
    @Published var systemAlarmStatus: String?
    private var lastAlarmSignature = ""

    private let buzzSteps = 7          // pulses after the main notification
    private let buzzSpacing = 6        // seconds between pulses (~42s total)

    /// Vibrate/pulse for ~40 seconds when a reminder fires, until stopped.
    @Published var buzzEnabled: Bool {
        didSet {
            UserDefaults.standard.set(buzzEnabled, forKey: "basma.buzz")
            if !buzzEnabled { AlertController.shared.stop() }
            schedule()
        }
    }

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
        nagMinutes = (UserDefaults.standard.object(forKey: nagKey) as? Int) ?? 10
        buzzEnabled = (UserDefaults.standard.object(forKey: "basma.buzz") as? Bool) ?? true
        systemAlarmEnabled = UserDefaults.standard.bool(forKey: "basma.sysAlarm")
        alarmSound = AlarmSound.current

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
        silenceActiveAlarms()
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

    /// Writes what the widget needs and asks it to refresh.
    private func publishSnapshot() {
        let oldest = DoneStorage.dayString(Date().addingTimeInterval(-86400))
        let recentDone = doneKeys.filter { String($0.prefix(10)) >= oldest }
        let snapshot = WidgetSnapshot(reminders: reminders,
                                      done: Array(recentDone),
                                      vacation: Array(vacationDays),
                                      updated: Date())
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// (Re)schedules the system alarms only when something relevant changed.
    func syncSystemAlarms(force: Bool = false) {
        let parts = reminders.map { "\($0.kind.rawValue)\($0.enabled)\($0.hour):\($0.minute)\($0.days.sorted())" }
        let signature = "\(systemAlarmEnabled)|\(isOnVacation)|\(alarmSound.rawValue)|" + parts.joined(separator: ";")
        if !force && signature == lastAlarmSignature { return }
        lastAlarmSignature = signature

        SystemAlarmBridge.sync(reminders: reminders, enabled: systemAlarmEnabled, paused: isOnVacation,
                               soundFile: alarmSound.fileName) { [weak self] active, message in
            guard let self = self else { return }
            let changed = self.systemAlarmActive != active
            self.systemAlarmActive = active
            self.systemAlarmStatus = message
            if changed { self.schedule() }      // buzz pulses depend on whether the real alarm is active
        }
    }

    func schedule() {
        publishSnapshot()
        syncSystemAlarms()
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
                             comps: DateComponents, repeats: Bool, loud: Bool = true) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        content.sound = loud ? alarmSound.notificationSound : .default
        content.categoryIdentifier = NotifID.category
        content.userInfo = ["kind": kind.rawValue]
        content.threadIdentifier = "basma-\(kind.rawValue)"
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
                                                            comps: c, repeats: false, loud: false)))
                        }
                    }
                }
            }
            items.sort { $0.0 < $1.0 }
            return items.prefix(46).map { $0.1 } + nagRequests(now: now) + buzzRequests(now: now)
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
                                           comps: lc, repeats: true, loud: false))
                }
            }
        }
        return out + nagRequests(now: now) + buzzRequests(now: now)
    }

    /// A chain of notifications every few seconds after the main one, so the phone keeps
    /// buzzing for ~40s even when locked. Only the next 2 alarms are prepared; stopping an
    /// alarm (button, tap, opening the app, marking done) removes the rest of its chain.
    private func buzzRequests(now: Date) -> [UNNotificationRequest] {
        guard buzzEnabled, !systemAlarmActive else { return [] }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let muted = DoneStorage.suppressedBuzz()
        let span = Double(buzzSteps * buzzSpacing)

        var alarms: [(fire: Date, reminder: FingerprintReminder, day: Date)] = []
        for offset in 0..<4 {
            guard let day = cal.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            if isVacationDay(day) { continue }
            if let rd = resumeDate, day < rd { continue }
            let wd = cal.component(.weekday, from: day)
            for r in reminders where r.enabled && r.days.contains(wd) {
                if isDone(r.kind, on: day) { continue }
                if muted.contains("\(DoneStorage.dayString(day))|\(r.kind.rawValue)") { continue }
                guard let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day) else { continue }
                if fire.addingTimeInterval(span) <= now { continue }
                alarms.append((fire, r, day))
            }
        }
        alarms.sort { $0.fire < $1.fire }

        var out: [UNNotificationRequest] = []
        for a in alarms.prefix(2) {
            for k in 1...buzzSteps {
                let t = a.fire.addingTimeInterval(Double(k * buzzSpacing))
                if t <= now { continue }
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: t)
                out.append(makeRequest(id: "buzz-\(a.reminder.kind.rawValue)-\(DoneStorage.dayString(a.day))-\(k)",
                                       kind: a.reminder.kind,
                                       body: "حان وقت \(a.reminder.kind.title) ✋ اضغط «إيقاف الاهتزاز»",
                                       comps: c, repeats: false))
            }
        }
        return out
    }

    /// Opening the app right after an alarm means you noticed it: stop its vibration chain.
    private func silenceActiveAlarms() {
        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        for r in reminders where r.enabled && r.days.contains(wd) {
            guard let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: now) else { continue }
            let elapsed = now.timeIntervalSince(fire)
            if elapsed >= 0 && elapsed <= 50 {
                DoneStorage.stopBuzz(kindRaw: r.kind.rawValue)
            }
        }
    }

    /// One-off "you haven't marked it yet" notifications for the next 3 days.
    /// They are cancelled for that day as soon as the fingerprint is marked done.
    private func nagRequests(now: Date) -> [UNNotificationRequest] {
        guard nagMinutes > 0 else { return [] }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        var out: [UNNotificationRequest] = []
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            if isVacationDay(day) { continue }
            if let rd = resumeDate, day < rd { continue }
            let wd = cal.component(.weekday, from: day)
            for r in reminders where r.enabled && r.days.contains(wd) {
                if isDone(r.kind, on: day) { continue }
                guard let base = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day) else { continue }
                let fire = base.addingTimeInterval(Double(nagMinutes * 60))
                if fire <= now { continue }
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                out.append(makeRequest(id: "nag-\(r.kind.rawValue)-\(DoneStorage.dayString(day))",
                                       kind: r.kind,
                                       body: "لم تبصم بعد؟ \(r.kind.title) ✋",
                                       comps: c, repeats: false))
            }
        }
        return out
    }

    // MARK: - History helpers

    private var earliestRecord: String? {
        doneKeys.compactMap { $0.split(separator: "|").first.map(String.init) }.min()
    }

    func hasHistory(on date: Date) -> Bool {
        guard let e = earliestRecord else { return false }
        return DoneStorage.dayString(date) >= e
    }

    func dayStat(for date: Date) -> DayStat {
        let kinds = scheduledKinds(on: date)
        let done = kinds.filter { isDone($0, on: date) }.count
        return DayStat(date: date, planned: kinds.count, done: done)
    }

    func clearHistory() {
        doneKeys = []
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "بصمتي"
        content.body = "هكذا سيظهر التذكير ✋ اسحب الإشعار لتظهر الأزرار"
        content.sound = alarmSound.notificationSound
        content.categoryIdentifier = NotifID.category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }
}
