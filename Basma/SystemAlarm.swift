import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
#endif

/// Thin wrapper so the rest of the app doesn't care whether AlarmKit (iOS 26+) exists.
enum SystemAlarmBridge {
    static var supported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// completion(active, message) is called on the main thread.
    static func sync(reminders: [FingerprintReminder], enabled: Bool, paused: Bool, soundFile: String?,
                     completion: @escaping (Bool, String?) -> Void) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task { @MainActor in
                let result = await AlarmCenter.shared.sync(reminders: reminders, enabled: enabled,
                                                           paused: paused, soundFile: soundFile)
                completion(result.0, result.1)
            }
            return
        }
        #endif
        _ = soundFile
        DispatchQueue.main.async {
            completion(false, enabled ? "منبّه النظام يحتاج iOS 26 أو أحدث." : nil)
        }
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
@MainActor
final class AlarmCenter {
    static let shared = AlarmCenter()
    private let idsKey = "basma.alarmIDs"

    private func savedIDs() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String]) ?? [:]
    }

    func sync(reminders: [FingerprintReminder], enabled: Bool, paused: Bool, soundFile: String?) async -> (Bool, String?) {
        let manager = AlarmManager.shared

        // Remove whatever we scheduled before
        for (_, idString) in savedIDs() {
            if let id = UUID(uuidString: idString) {
                try? manager.cancel(id: id)
            }
        }
        UserDefaults.standard.removeObject(forKey: idsKey)

        guard enabled else { return (false, nil) }
        if paused { return (false, "وضع الإجازة مفعّل، المنبّهات متوقفة مؤقتاً.") }

        // Permission
        var state = manager.authorizationState
        if state == .notDetermined {
            state = (try? await manager.requestAuthorization()) ?? .denied
        }
        guard state == .authorized else {
            return (false, "اسمح لبصمتي بالمنبّهات من إعدادات الآيفون.")
        }

        var ids: [String: String] = [:]
        var count = 0
        for r in reminders where r.enabled && !r.days.isEmpty {
            let id = UUID()
            do {
                try await schedule(id: id, reminder: r, soundFile: soundFile)
                ids[r.kind.rawValue] = id.uuidString
                count += 1
            } catch {
                UserDefaults.standard.set(ids, forKey: idsKey)
                return (false, "تعذّر ضبط المنبّه: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(ids, forKey: idsKey)
        return (count > 0, count > 0 ? "تم ضبط \(count) منبّهات في النظام" : "لا توجد تذكيرات مفعّلة.")
    }

    private func weekday(_ n: Int) -> Locale.Weekday? {
        switch n {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    private func title(for kind: ReminderKind) -> LocalizedStringResource {
        switch kind {
        case .entry: return "بصمة الدخول"
        case .presence: return "بصمة التواجد"
        case .exit: return "بصمة الخروج"
        }
    }

    private func schedule(id: UUID, reminder r: FingerprintReminder, soundFile: String?) async throws {
        let weekdays = r.days.sorted().compactMap { weekday($0) }
        let time = Alarm.Schedule.Relative.Time(hour: r.hour, minute: r.minute)
        let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(weekdays)
        let schedule = Alarm.Schedule.relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))

        let stopButton = AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.circle.fill")
        let alert = AlarmPresentation.Alert(title: title(for: r.kind), stopButton: stopButton)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: BasmaAlarmData(title: r.kind.title),
            tintColor: Color(hex: 0x7C83FF)
        )
        let sound: AlertConfiguration.AlertSound
        if let soundFile = soundFile {
            sound = .named(soundFile)
        } else {
            sound = .default
        }
        let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attributes, sound: sound)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}
#endif
