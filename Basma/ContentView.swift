import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var editing: ReminderKind?
    @State private var showQuick = false
    @State private var showVacation = false
    @AppStorage("basma.onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    if store.permissionDenied { permissionBanner }
                    if store.isOnVacation { VacationBanner() }

                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HeroCard(next: store.nextUpcoming())
                    }

                    todaySection
                    statsSection
                    remindersSection
                    quickButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { kind in
            EditSheet(kind: kind)
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showQuick) {
            QuickSetupSheet()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showVacation) {
            VacationSheet()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.dark)
        }
        .onAppear {
            if !onboarded {
                onboarded = true
                showQuick = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("بصمتي")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(todayString)
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            }
            Spacer()
            Menu {
                Button { showQuick = true } label: {
                    Label("ضبط سريع للدوام", systemImage: "wand.and.stars")
                }
                Button { showVacation = true } label: {
                    Label("وضع الإجازة", systemImage: "beach.umbrella")
                }
                Button { store.sendTest() } label: {
                    Label("تجربة إشعار بعد 5 ثواني", systemImage: "bell.badge")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 6)
    }

    private var todayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "EEEE، d MMMM"
        return f.string(from: Date())
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("الإشعارات مغلقة", systemImage: "bell.slash.fill")
                .font(.headline)
            Text("فعّل الإشعارات للتطبيق من الإعدادات حتى تصلك التذكيرات.")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
            Button("فتح الإعدادات") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.red.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("بصمات اليوم")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                if !store.todayKinds.isEmpty {
                    Text("\(arNum(store.doneTodayCount)) من \(arNum(store.todayKinds.count))")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }

            if store.todayKinds.isEmpty {
                Text(store.isVacationDay(Date()) ? "اليوم إجازة 🌴 استمتع بوقتك" : "لا توجد بصمات مجدولة اليوم 🎉")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.todayKinds) { r in
                        TodayRow(reminder: r) { editing = r.kind }
                    }
                }
            }
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("إحصائياتك")
                .font(.system(.title3, design: .rounded).weight(.bold))
            StatsCard()
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("التذكيرات")
                .font(.system(.title3, design: .rounded).weight(.bold))

            VStack(spacing: 10) {
                ForEach(ReminderKind.allCases) { kind in
                    ReminderRow(kind: kind) { editing = kind }
                }
            }
            Text("اضغط على أي تذكير لتعديل الوقت والأيام")
                .font(.footnote)
                .foregroundColor(Theme.muted)
        }
    }

    private var quickButton: some View {
        Button { showQuick = true } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("ضبط سريع للدوام")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent2],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .foregroundColor(.white)
        }
    }
}

// MARK: - Hero

struct HeroCard: View {
    let next: (reminder: FingerprintReminder, date: Date)?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((next?.reminder.kind.tint ?? Theme.accent).opacity(0.18))
                    .frame(width: 92, height: 92)
                    .scaleEffect(pulse ? 1.18 : 0.96)
                Circle()
                    .fill((next?.reminder.kind.tint ?? Theme.accent).opacity(0.28))
                    .frame(width: 72, height: 72)
                Image(systemName: "touchid")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            if let n = next {
                Text("البصمة القادمة")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
                Text(n.reminder.kind.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(dayLabel(for: n.date)) • \(timeString(n.reminder.hour, n.reminder.minute))")
                    .font(.headline)
                    .foregroundColor(n.reminder.kind.tint)
                HStack(spacing: 4) {
                    Text("بعد")
                    Text(n.date, style: .relative)
                }
                .font(.subheadline)
                .foregroundColor(Theme.muted)
            } else {
                Text("لا توجد بصمات قادمة")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("فعّل تذكيراً أو استخدم الضبط السريع")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card(padding: 8)
    }
}

// MARK: - Rows

struct TodayRow: View {
    @EnvironmentObject var store: ReminderStore
    let reminder: FingerprintReminder
    let onEdit: () -> Void

    var body: some View {
        let done = store.isDoneToday(reminder.kind)
        HStack(spacing: 14) {
            Button {
                haptic()
                withAnimation(.spring()) { store.toggleDone(reminder.kind) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundColor(done ? reminder.kind.tint : Color.white.opacity(0.3))
            }

            Button(action: onEdit) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reminder.kind.title)
                            .font(.system(.headline, design: .rounded))
                            .strikethrough(done)
                            .foregroundColor(done ? Theme.muted : .white)
                        Text(timeString(reminder.hour, reminder.minute))
                            .font(.subheadline)
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: reminder.kind.icon)
                        .font(.title2)
                        .foregroundColor(reminder.kind.tint.opacity(done ? 0.4 : 1))
                }
            }
            .buttonStyle(.plain)
        }
        .card(padding: 14)
    }
}

struct ReminderRow: View {
    @EnvironmentObject var store: ReminderStore
    let kind: ReminderKind
    let onEdit: () -> Void

    var body: some View {
        let binding = store.binding(for: kind)
        let r = binding.wrappedValue
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(kind.tint.opacity(0.2)).frame(width: 46, height: 46)
                        Image(systemName: kind.icon)
                            .font(.title3)
                            .foregroundColor(kind.tint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title)
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(timeString(r.hour, r.minute)) • \(daysSummary(r.days))")
                            .font(.footnote)
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { binding.wrappedValue.enabled },
                set: { v in
                    var x = binding.wrappedValue
                    x.enabled = v
                    binding.wrappedValue = x
                }
            ))
            .labelsHidden()
            .tint(kind.tint)
        }
        .opacity(r.enabled ? 1 : 0.55)
        .card(padding: 14)
    }
}

// MARK: - Edit sheet

struct EditSheet: View {
    let kind: ReminderKind
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    private let leads = [0, 5, 10, 15, 30]

    var body: some View {
        let b = store.binding(for: kind)
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(kind.tint.opacity(0.22)).frame(width: 52, height: 52)
                            Image(systemName: kind.icon)
                                .font(.title2)
                                .foregroundColor(kind.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text(kind.subtitle)
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { b.wrappedValue.enabled },
                            set: { v in
                                var x = b.wrappedValue
                                x.enabled = v
                                b.wrappedValue = x
                            }
                        ))
                        .labelsHidden()
                        .tint(kind.tint)
                    }
                    .padding(.top, 20)

                    // Time
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("الوقت")
                        DatePicker("", selection: Binding(
                            get: { b.wrappedValue.timeDate },
                            set: { newValue in
                                var x = b.wrappedValue
                                x.timeDate = newValue
                                b.wrappedValue = x
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ar"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                    }
                    .card()

                    // Days
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("الأيام")
                        HStack(spacing: 8) {
                            presetButton("أيام الدوام", set: [1, 2, 3, 4, 5], binding: b)
                            presetButton("كل الأيام", set: Set(1...7), binding: b)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(weekdayNames, id: \.0) { item in
                                let on = b.wrappedValue.days.contains(item.0)
                                Button {
                                    haptic(.light)
                                    var x = b.wrappedValue
                                    if on { x.days.remove(item.0) } else { x.days.insert(item.0) }
                                    b.wrappedValue = x
                                } label: {
                                    Text(item.1)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(on ? kind.tint : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(on ? Color.black.opacity(0.85) : .white)
                                }
                            }
                        }
                    }
                    .card()

                    // Lead
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("تنبيه مسبق")
                        HStack(spacing: 8) {
                            ForEach(leads, id: \.self) { m in
                                let on = b.wrappedValue.leadMinutes == m
                                Button {
                                    haptic(.light)
                                    var x = b.wrappedValue
                                    x.leadMinutes = m
                                    b.wrappedValue = x
                                } label: {
                                    Text(m == 0 ? "بدون" : "\(arNum(m)) د")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(
                                            Capsule().fill(on ? kind.tint : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(on ? Color.black.opacity(0.85) : .white)
                                }
                            }
                        }
                        Text(b.wrappedValue.leadMinutes == 0
                             ? "سيصلك إشعار واحد في الوقت المحدد."
                             : "سيصلك إشعار قبل الموعد بـ \(arNum(b.wrappedValue.leadMinutes)) دقائق، وآخر في الموعد.")
                            .font(.footnote)
                            .foregroundColor(Theme.muted)
                    }
                    .card()

                    Button { dismiss() } label: {
                        Text("تم")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.tint)
                            )
                            .foregroundColor(Color.black.opacity(0.85))
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundColor(Theme.muted)
    }

    private func presetButton(_ title: String, set: Set<Int>, binding: Binding<FingerprintReminder>) -> some View {
        let on = binding.wrappedValue.days == set
        return Button {
            haptic(.light)
            var x = binding.wrappedValue
            x.days = set
            binding.wrappedValue = x
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.1)))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Quick setup

struct QuickSetupSheet: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var presence = Date()
    @State private var end = Date()
    @State private var days: Set<Int> = [1, 2, 3, 4, 5]
    @State private var lead = 5
    @State private var loaded = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 34))
                            .foregroundColor(Theme.accent)
                        Text("ضبط سريع للدوام")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("حدد أوقاتك مرة واحدة وتنضبط كل التذكيرات")
                            .font(.subheadline)
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 14) {
                        timeRow(.entry, "بداية الدوام (الدخول)", $start)
                        Divider().overlay(Color.white.opacity(0.1))
                        timeRow(.presence, "بصمة التواجد", $presence)
                        Divider().overlay(Color.white.opacity(0.1))
                        timeRow(.exit, "نهاية الدوام (الخروج)", $end)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("أيام الدوام")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.muted)
                        HStack(spacing: 8) {
                            chip("الأحد – الخميس", on: days == Set([1, 2, 3, 4, 5])) { days = [1, 2, 3, 4, 5] }
                            chip("كل الأيام", on: days.count == 7) { days = Set(1...7) }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(weekdayNames, id: \.0) { item in
                                let on = days.contains(item.0)
                                Button {
                                    haptic(.light)
                                    if on { days.remove(item.0) } else { days.insert(item.0) }
                                } label: {
                                    Text(item.1)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(on ? Theme.accent : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("تنبيه مسبق قبل كل بصمة")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.muted)
                        HStack(spacing: 8) {
                            ForEach([0, 5, 10, 15, 30], id: \.self) { m in
                                chip(m == 0 ? "بدون" : "\(arNum(m)) د", on: lead == m, full: true) { lead = m }
                            }
                        }
                    }
                    .card()

                    Button {
                        haptic()
                        store.applyQuick(start: start, presence: presence, end: end, days: days, lead: lead)
                        dismiss()
                    } label: {
                        Text("حفظ وتفعيل التذكيرات")
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
                    .disabled(days.isEmpty)
                    .opacity(days.isEmpty ? 0.5 : 1)

                    Button("لاحقاً") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(Theme.muted)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            start = store.reminder(.entry).timeDate
            presence = store.reminder(.presence).timeDate
            end = store.reminder(.exit).timeDate
            let d = store.reminder(.entry).days
            if !d.isEmpty { days = d }
            lead = store.reminder(.entry).leadMinutes
        }
    }

    private func timeRow(_ kind: ReminderKind, _ title: String, _ date: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(kind.tint.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: kind.icon).foregroundColor(kind.tint)
            }
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }

    private func chip(_ title: String, on: Bool, full: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            haptic(.light)
            action()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: full ? .infinity : nil, minHeight: 36)
                .padding(.horizontal, full ? 0 : 14)
                .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.1)))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Time formatting

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
