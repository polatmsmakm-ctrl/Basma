import Foundation
import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Models (shared by the app and the widget)

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

    var tint: Color {
        switch self {
        case .entry: return Color(hex: 0x34D399)
        case .presence: return Color(hex: 0xFBBF24)
        case .exit: return Color(hex: 0xFB7185)
        }
    }

    var subtitle: String {
        switch self {
        case .entry: return "عند وصولك للعمل"
        case .presence: return "خلال الدوام"
        case .exit: return "عند انصرافك"
        }
    }
}

extension ReminderKind: Identifiable {
    var id: String { rawValue }
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

// MARK: - Snapshot shared with the widget (through an App Group)

struct WidgetSnapshot: Codable {
    var reminders: [FingerprintReminder]
    var done: [String]          // "yyyy-MM-dd|kind"
    var vacation: [String]      // "yyyy-MM-dd"
    var updated: Date
}

enum SharedStore {
    static let group = "group.com.rashid.basma"
    private static let key = "basma.widget.snapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? UserDefaults.standard
    }

    static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct WidgetSlot: Identifiable {
    let kind: ReminderKind
    let hour: Int
    let minute: Int
    let done: Bool
    var id: String { kind.rawValue }
}

struct WidgetNext {
    let kind: ReminderKind
    let fire: Date
}

enum WidgetLogic {
    static func isVacation(_ s: WidgetSnapshot, _ date: Date) -> Bool {
        s.vacation.contains(SharedStore.dayString(date))
    }

    static func isDone(_ s: WidgetSnapshot, _ kind: ReminderKind, _ date: Date) -> Bool {
        s.done.contains("\(SharedStore.dayString(date))|\(kind.rawValue)")
    }

    static func today(_ s: WidgetSnapshot, now: Date) -> [WidgetSlot] {
        if isVacation(s, now) { return [] }
        let wd = Calendar.current.component(.weekday, from: now)
        return s.reminders
            .filter { $0.enabled && $0.days.contains(wd) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            .map { WidgetSlot(kind: $0.kind, hour: $0.hour, minute: $0.minute, done: isDone(s, $0.kind, now)) }
    }

    static func next(_ s: WidgetSnapshot, now: Date) -> WidgetNext? {
        let cal = Calendar.current
        var best: WidgetNext?
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            if isVacation(s, day) { continue }
            let wd = cal.component(.weekday, from: day)
            for r in s.reminders where r.enabled && r.days.contains(wd) {
                guard let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day),
                      fire > now else { continue }
                if offset == 0 && isDone(s, r.kind, now) { continue }
                if best == nil || fire < best!.fire {
                    best = WidgetNext(kind: r.kind, fire: fire)
                }
            }
        }
        return best
    }
}

// MARK: - AlarmKit metadata (iOS 26+, shared so the widget can render the alarm)

#if canImport(AlarmKit)
import AlarmKit

struct BasmaAlarmData: AlarmMetadata {
    var title: String
}
#endif
