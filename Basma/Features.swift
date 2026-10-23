import SwiftUI

// MARK: - Stats card

struct StatsCard: View {
    @EnvironmentObject var store: ReminderStore

    var body: some View {
        let week = store.weekStats()
        let streak = store.streak
        let planned = week.reduce(0) { $0 + $1.planned }
        let done = week.reduce(0) { $0 + $1.done }
        let pct = planned == 0 ? 0 : Int((Double(done) / Double(planned) * 100).rounded())

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                tile(icon: "flame.fill", color: Color(hex: 0xFB923C),
                     value: arNum(streak),
                     label: streak == 1 ? "يوم متتالي" : "أيام متتالية")
                tile(icon: "chart.pie.fill", color: Theme.accent,
                     value: "\(arNum(pct))٪",
                     label: "التزام آخر ٧ أيام")
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week) { d in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 56)
                            Capsule()
                                .fill(barColor(d))
                                .frame(height: barHeight(d))
                        }
                        Text(initial(d.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Calendar.current.isDateInToday(d.date) ? .white : Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    private func tile(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption2)
                    .foregroundColor(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func barHeight(_ d: DayStat) -> CGFloat {
        if d.planned == 0 { return 6 }
        return max(8, 56 * CGFloat(d.fraction))
    }

    private func barColor(_ d: DayStat) -> Color {
        if d.planned == 0 { return Color.white.opacity(0.2) }
        if d.fraction >= 1 { return Color(hex: 0x34D399) }
        if d.fraction > 0 { return Color(hex: 0xFBBF24) }
        return Color(hex: 0xFB7185).opacity(0.7)
    }

    private func initial(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}

// MARK: - Vacation banner

struct VacationBanner: View {
    @EnvironmentObject var store: ReminderStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "beach.umbrella.fill")
                .font(.title)
                .foregroundColor(Color(hex: 0xFBBF24))
            VStack(alignment: .leading, spacing: 3) {
                Text("وضع الإجازة مفعّل")
                    .font(.system(.headline, design: .rounded))
                if let r = store.resumeDate {
                    Text("تعود التذكيرات \(vacationDateText(r))")
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                }
            }
            Spacer()
            Button {
                haptic()
                store.endVacation()
            } label: {
                Text("إنهاء")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xFBBF24).opacity(0.45), lineWidth: 1)
        )
    }
}

func vacationDateText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ar")
    f.dateFormat = "EEEE d MMMM"
    return f.string(from: date)
}

// MARK: - Vacation sheet

struct VacationSheet: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    @State private var lastDay = Calendar.current.startOfDay(for: Date())

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private let quick: [(String, Int)] = [
        ("اليوم فقط", 0), ("غداً", 1), ("٣ أيام", 2), ("أسبوع", 6), ("أسبوعان", 13)
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "beach.umbrella.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Color(hex: 0xFBBF24))
                        Text("وضع الإجازة")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("توقف كل التذكيرات وترجع تلقائياً بعد انتهاء الإجازة")
                            .font(.subheadline)
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("مدة الإجازة")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(quick, id: \.1) { item in
                                let target = Calendar.current.date(byAdding: .day, value: item.1, to: today) ?? today
                                let on = Calendar.current.isDate(lastDay, inSameDayAs: target)
                                Button {
                                    haptic(.light)
                                    lastDay = target
                                } label: {
                                    Text(item.0)
                                        .font(.footnote.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 38)
                                        .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.1)))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("آخر يوم في الإجازة")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.muted)
                        DatePicker("", selection: $lastDay, in: today..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ar"))
                            .tint(Theme.accent)
                    }
                    .card()

                    let resume = Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
                    Text("تعود التذكيرات \(vacationDateText(resume))")
                        .font(.footnote)
                        .foregroundColor(Theme.muted)

                    Button {
                        haptic()
                        store.startVacation(lastDay: lastDay)
                        dismiss()
                    } label: {
                        Text(store.isOnVacation ? "تحديث الإجازة" : "تفعيل وضع الإجازة")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent2],
                                                         startPoint: .leading, endPoint: .trailing))
                            )
                            .foregroundColor(.white)
                    }

                    if store.isOnVacation {
                        Button("إنهاء الإجازة الآن") {
                            haptic()
                            store.endVacation()
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0xFB7185))
                    }

                    Button("إغلاق") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(Theme.muted)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
    }
}
