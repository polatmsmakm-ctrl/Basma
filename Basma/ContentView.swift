import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ReminderStore

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if store.permissionDenied {
                        permissionBanner
                    }
                    todayCard
                    ForEach(store.reminders.indices, id: \.self) { i in
                        ReminderCard(reminder: $store.reminders[i])
                    }
                    Button {
                        store.sendTest()
                    } label: {
                        Label("تجربة إشعار بعد 5 ثواني", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(14)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("بصمتي")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("الإشعارات مغلقة")
                .font(.headline)
            Text("فعّل الإشعارات للتطبيق من الإعدادات حتى تصلك التذكيرات.")
                .font(.subheadline)
            Button("فتح الإعدادات") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.12))
        .cornerRadius(14)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("بصمات اليوم")
                .font(.headline)
            if store.todayKinds.isEmpty {
                Text("لا توجد تذكيرات مفعّلة اليوم 🎉")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.todayKinds) { r in
                    Button {
                        store.toggleDone(r.kind)
                    } label: {
                        HStack {
                            Image(systemName: store.isDoneToday(r.kind) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(store.isDoneToday(r.kind) ? .green : .gray)
                                .font(.title3)
                            Text(r.kind.title)
                                .foregroundColor(.primary)
                                .strikethrough(store.isDoneToday(r.kind))
                            Spacer()
                            Text(timeString(r.hour, r.minute))
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct ReminderCard: View {
    @Binding var reminder: FingerprintReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: reminder.kind.icon)
                    .font(.title2)
                    .foregroundColor(reminder.kind.color)
                Text(reminder.kind.title)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $reminder.enabled)
                    .labelsHidden()
            }

            if reminder.enabled {
                HStack {
                    Text("الوقت")
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { reminder.timeDate },
                        set: { reminder.timeDate = $0 }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ar"))
                }

                Stepper(value: $reminder.leadMinutes, in: 0...30, step: 5) {
                    Text(reminder.leadMinutes == 0
                         ? "بدون تنبيه مسبق"
                         : "تنبيه مسبق قبل \(reminder.leadMinutes) دقائق")
                        .font(.subheadline)
                }

                HStack(spacing: 6) {
                    ForEach(weekdayNames, id: \.0) { (num, name) in
                        let on = reminder.days.contains(num)
                        Text(String(name.prefix(2)))
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(on ? reminder.kind.color : Color(.tertiarySystemFill))
                            .foregroundColor(on ? .white : .primary)
                            .cornerRadius(10)
                            .onTapGesture {
                                if on { reminder.days.remove(num) } else { reminder.days.insert(num) }
                            }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .animation(.easeInOut(duration: 0.2), value: reminder.enabled)
    }
}

func timeString(_ h: Int, _ m: Int) -> String {
    var comps = DateComponents()
    comps.hour = h
    comps.minute = m
    let date = Calendar.current.date(from: comps) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "ar")
    f.timeStyle = .short
    return f.string(from: date)
}
