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

enum Theme {
    static let bgTop = Color(hex: 0x0B1020)
    static let bgBottom = Color(hex: 0x1B1740)
    static let accent = Color(hex: 0x7C83FF)
    static let accent2 = Color(hex: 0xB07CFF)
    static let muted = Color.white.opacity(0.6)
}

extension ReminderKind: Identifiable {
    var id: String { rawValue }

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

// MARK: - Shared views

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 140, y: -260)
            Circle()
                .fill(Theme.accent2.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -150, y: 300)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Helpers

func arNum(_ n: Int) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "ar")
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

func daysSummary(_ days: Set<Int>) -> String {
    if days.isEmpty { return "لا يوجد أيام" }
    if days.count == 7 { return "كل الأيام" }
    if days == Set([1, 2, 3, 4, 5]) { return "من الأحد إلى الخميس" }
    return weekdayNames.filter { days.contains($0.0) }.map { $0.1 }.joined(separator: "، ")
}

func dayLabel(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "اليوم" }
    if cal.isDateInTomorrow(date) { return "غداً" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ar")
    f.dateFormat = "EEEE"
    return f.string(from: date)
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Store extras

extension ReminderStore {
    func binding(for kind: ReminderKind) -> Binding<FingerprintReminder> {
        Binding(
            get: { self.reminders.first(where: { $0.kind == kind })
                    ?? FingerprintReminder(kind: kind, enabled: false, hour: 8, minute: 0, days: [], leadMinutes: 0) },
            set: { newValue in
                if let i = self.reminders.firstIndex(where: { $0.kind == kind }) {
                    self.reminders[i] = newValue
                }
            }
        )
    }

    func reminder(_ kind: ReminderKind) -> FingerprintReminder {
        binding(for: kind).wrappedValue
    }

    func nextUpcoming() -> (reminder: FingerprintReminder, date: Date)? {
        let cal = Calendar.current
        let now = Date()
        var best: (reminder: FingerprintReminder, date: Date)?
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            if isVacationDay(day) { continue }
            let wd = cal.component(.weekday, from: day)
            for r in reminders where r.enabled && r.days.contains(wd) {
                guard let fire = cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day),
                      fire > now else { continue }
                if offset == 0 && isDoneToday(r.kind) { continue }
                if best == nil || fire < best!.date { best = (r, fire) }
            }
        }
        return best
    }

    var doneTodayCount: Int {
        todayKinds.filter { isDoneToday($0.kind) }.count
    }

    func applyQuick(start: Date, presence: Date, end: Date, days: Set<Int>, lead: Int) {
        let cal = Calendar.current
        func set(_ kind: ReminderKind, _ date: Date) {
            var r = reminder(kind)
            let c = cal.dateComponents([.hour, .minute], from: date)
            r.hour = c.hour ?? r.hour
            r.minute = c.minute ?? r.minute
            r.days = days
            r.leadMinutes = lead
            r.enabled = true
            binding(for: kind).wrappedValue = r
        }
        set(.entry, start)
        set(.presence, presence)
        set(.exit, end)
    }
}
