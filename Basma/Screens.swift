import SwiftUI

// MARK: - Root (tabs)

struct ContentView: View {
    @EnvironmentObject var store: ReminderStore
    @ObservedObject private var alert = AlertController.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("الرئيسية", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("السجل", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: Binding<ReminderKind?>(
            get: { alert.activeKind },
            set: { newValue in if newValue == nil { alert.stop() } }
        )) { kind in
            AlertView(kind: kind)
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var monthOffset = 0

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var monthStart: Date {
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: monthStart)
    }

    /// nil entries are leading blanks so day 1 lands under the right weekday (Sunday first).
    private var cells: [Date?] {
        let first = monthStart
        let blanks = cal.component(.weekday, from: first) - 1
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: blanks)
        for i in 0..<count {
            out.append(cal.date(byAdding: .day, value: i, to: first))
        }
        return out
    }

    private var monthPercent: Int {
        var planned = 0
        var done = 0
        let today = cal.startOfDay(for: Date())
        for case let day? in cells {
            if day > today || !store.hasHistory(on: day) { continue }
            let s = store.dayStat(for: day)
            planned += s.planned
            done += s.done
        }
        return planned == 0 ? 0 : Int((Double(done) / Double(planned) * 100).rounded())
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack {
                        Text("السجل")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.top, 6)

                    HStack(spacing: 12) {
                        summaryTile(icon: "checkmark.seal.fill", color: Color(hex: 0x34D399),
                                    value: arNum(store.doneKeys.count), label: "بصمة مسجّلة")
                        summaryTile(icon: "flame.fill", color: Color(hex: 0xFB923C),
                                    value: arNum(store.streak), label: "أيام متتالية")
                    }

                    VStack(spacing: 14) {
                        HStack {
                            Button {
                                haptic(.light)
                                if monthOffset > -12 { monthOffset -= 1 }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Text(monthTitle)
                                    .font(.system(.headline, design: .rounded))
                                Text("التزام الشهر: \(arNum(monthPercent))٪")
                                    .font(.caption)
                                    .foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Button {
                                haptic(.light)
                                if monthOffset < 0 { monthOffset += 1 }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                            }
                            .opacity(monthOffset < 0 ? 1 : 0.3)
                        }
                        .foregroundColor(.white)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(weekdayNames, id: \.0) { item in
                                Text(String(item.1.prefix(2)))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Theme.muted)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                                if let day = day {
                                    dayCell(day)
                                } else {
                                    Color.clear.frame(height: 40)
                                }
                            }
                        }
                    }
                    .card()

                    legend
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Theme.bgTop, for: .tabBar)
    }

    // MARK: pieces

    private func dayCell(_ day: Date) -> some View {
        let today = cal.startOfDay(for: Date())
        let isToday = cal.isDate(day, inSameDayAs: today)
        let isFuture = day > today
        let s = store.dayStat(for: day)
        let vacation = store.isVacationDay(day)
        let tracked = store.hasHistory(on: day)

        var fill = Color.white.opacity(0.05)
        var textColor = Theme.muted
        if vacation {
            fill = Color(hex: 0x60A5FA).opacity(0.35)
            textColor = .white
        } else if !isFuture && tracked && s.planned > 0 {
            if s.fraction >= 1 {
                fill = Color(hex: 0x34D399)
                textColor = Color.black.opacity(0.85)
            } else if s.fraction > 0 {
                fill = Color(hex: 0xFBBF24)
                textColor = Color.black.opacity(0.85)
            } else if !isToday {
                fill = Color(hex: 0xFB7185).opacity(0.75)
                textColor = .white
            }
        }

        return Text(arNum(cal.component(.day, from: day)))
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Circle().fill(fill))
            .overlay(
                Circle().stroke(Color.white.opacity(isToday ? 0.9 : 0), lineWidth: 2)
            )
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Color(hex: 0x34D399), "مكتمل")
            legendItem(Color(hex: 0xFBBF24), "جزئي")
            legendItem(Color(hex: 0xFB7185).opacity(0.75), "فائت")
            legendItem(Color(hex: 0x60A5FA).opacity(0.5), "إجازة")
        }
        .font(.caption)
        .foregroundColor(Theme.muted)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func summaryTile(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption2)
                    .foregroundColor(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: ReminderStore
    @ObservedObject private var loc = WorkLocation.shared
    @ObservedObject private var player = SoundPlayer.shared
    @State private var showQuick = false
    @State private var showVacation = false
    @State private var confirmReset = false

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack {
                        Text("الإعدادات")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.top, 6)

                    alarmCard
                    soundCard
                    buzzCard
                    locationCard
                    nagCard
                    widgetCard
                    toolsCard
                    notificationsCard
                    dataCard

                    Text("بصمتي • الإصدار \(arNumString(version))")
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Theme.bgTop, for: .tabBar)
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
        .confirmationDialog("مسح سجل البصمات؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("مسح السجل", role: .destructive) {
                store.clearHistory()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيُحذف سجل ما بصمت عليه والإحصائيات. التذكيرات تبقى كما هي.")
        }
    }

    // MARK: cards

    // MARK: system alarm (iOS 26)

    private var alarmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill")
                    .foregroundColor(Color(hex: 0xFBBF24))
                Text("منبّه النظام")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $store.systemAlarmEnabled)
                    .labelsHidden()
                    .tint(Color(hex: 0xFBBF24))
                    .disabled(!SystemAlarmBridge.supported)
            }
            if SystemAlarmBridge.supported {
                Text("منبّه حقيقي مثل منبّه الساعة: يرن ويهتز لين توقفه، حتى لو الجوال مقفل أو صامت.")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
                if let status = store.systemAlarmStatus {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(store.systemAlarmActive ? Color(hex: 0x34D399) : Color(hex: 0xFBBF24))
                }
            } else {
                Text("هذه الميزة تحتاج iOS 26 أو أحدث.")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: sound

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(Color(hex: 0xFB923C))
                Text("صوت المنبّه")
                    .font(.system(.headline, design: .rounded))
            }
            Text("اختر الصوت اللي يشتغل مع التذكيرات ومنبّه النظام وشاشة الاهتزاز. اضغط ▶ للمعاينة.")
                .font(.footnote)
                .foregroundColor(Theme.muted)

            VStack(spacing: 8) {
                ForEach(AlarmSound.allCases) { sound in
                    soundRow(sound)
                }
            }
            .padding(.top, 4)

            Text("بعد التغيير يُحدَّث ضبط التذكيرات تلقائياً. صوت الإشعار نفسه قد يتأخر تطبيقه لحين وصول الإشعار القادم.")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func soundRow(_ sound: AlarmSound) -> some View {
        let selected = store.alarmSound == sound
        let playing = player.previewing == sound
        return HStack(spacing: 12) {
            Button {
                haptic(.light)
                store.alarmSound = sound
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.title3)
                        .foregroundColor(selected ? Theme.accent : Color.white.opacity(0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sound.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.white)
                        Text(sound.subtitle)
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                haptic(.light)
                if playing {
                    player.stop()
                } else {
                    player.play(sound, loop: false)
                }
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.footnote)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .foregroundColor(.white)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05))
        )
    }

    // MARK: location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .foregroundColor(Color(hex: 0x60A5FA))
                Text("تذكير الموقع")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $loc.enabled)
                    .labelsHidden()
                    .tint(Color(hex: 0x60A5FA))
                    .disabled(!loc.hasWorkplace)
            }
            Text("يذكّرك بالبصمة أول ما توصل للدوام، وبالخروج لما تغادر.")
                .font(.footnote)
                .foregroundColor(Theme.muted)

            Button {
                haptic()
                loc.saveCurrentAsWorkplace()
            } label: {
                Label(loc.hasWorkplace ? "تحديث موقع الدوام (أنا هنا الآن)" : "حدد موقعي الحالي كموقع الدوام",
                      systemImage: "mappin.and.ellipse")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white)
            }

            if loc.hasWorkplace {
                HStack(spacing: 8) {
                    ForEach([100.0, 150.0, 250.0, 400.0], id: \.self) { m in
                        let on = loc.radius == m
                        Button {
                            haptic(.light)
                            loc.radius = m
                        } label: {
                            Text("\(arNum(Int(m))) م")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Capsule().fill(on ? Color(hex: 0x60A5FA) : Color.white.opacity(0.1)))
                                .foregroundColor(on ? Color.black.opacity(0.85) : .white)
                        }
                    }
                }
                Text("المسافة حول الدوام اللي تعتبر «وصلت». الأفضل ١٥٠ م أو أكثر.")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }

            if loc.enabled && loc.authStatus != .authorizedAlways {
                VStack(alignment: .leading, spacing: 6) {
                    Text("لازم تختار «دائماً» في إذن الموقع حتى يشتغل والتطبيق مقفل.")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(hex: 0xFBBF24))
                    Button("فتح إعدادات الموقع") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.bold))
                }
            }

            if let m = loc.message {
                Text(m)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(hex: 0x34D399))
            }

            if loc.hasWorkplace {
                Button("حذف موقع الدوام") {
                    loc.clearWorkplace()
                }
                .font(.caption)
                .foregroundColor(Color(hex: 0xFB7185))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: widget

    private var widgetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(Theme.accent2)
                Text("ويدجت الشاشة الرئيسية")
                    .font(.system(.headline, design: .rounded))
            }
            Text("اضغط مطولاً على فراغ في الشاشة الرئيسية ← زر + ← ابحث عن «بصمتي». يعرض البصمة القادمة وحالة بصمات اليوم، ويتوفر أيضاً في شاشة القفل.")
                .font(.footnote)
                .foregroundColor(Theme.muted)
            Text("إذا ما ظهر الويدجت أو ظهرت «افتح بصمتي»، فالنسخة المثبتة هي «Lite» بدون ويدجت.")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var buzzCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .foregroundColor(Color(hex: 0xFB7185))
                Text("اهتزاز ٤٠ ثانية")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $store.buzzEnabled)
                    .labelsHidden()
                    .tint(Color(hex: 0xFB7185))
            }
            Text("لما يجي وقت البصمة يهتز الجوال لين تضغط «إيقاف» أو «تمت البصمة»، وأقصى مدة ٤٠ ثانية.")
                .font(.footnote)
                .foregroundColor(Theme.muted)
            Text("داخل التطبيق: اهتزاز متواصل مع شاشة إيقاف كبيرة. والجوال مقفل: نبضات اهتزاز كل ٦ ثواني تقريباً (قيد من نظام iOS).")
                .font(.caption)
                .foregroundColor(Theme.muted)
            Button {
                haptic()
                AlertController.shared.start(kind: .entry, force: true)
            } label: {
                Label("تجربة الاهتزاز الآن", systemImage: "waveform")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var nagCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(Theme.accent)
                Text("التذكير المتكرر")
                    .font(.system(.headline, design: .rounded))
            }
            Text("إذا ما علّمت على البصمة، يرجع التذكير بعد:")
                .font(.footnote)
                .foregroundColor(Theme.muted)
            HStack(spacing: 8) {
                ForEach([0, 5, 10, 15, 20], id: \.self) { m in
                    let on = store.nagMinutes == m
                    Button {
                        haptic(.light)
                        store.nagMinutes = m
                    } label: {
                        Text(m == 0 ? "إيقاف" : "\(arNum(m)) د")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.1)))
                            .foregroundColor(.white)
                    }
                }
            }
            Text("يتوقف التذكير تلقائياً لما تضغط «تمت البصمة» من الإشعار أو من التطبيق.")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var toolsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "wand.and.stars", color: Theme.accent2,
                       title: "ضبط سريع للدوام", subtitle: "أوقات الدخول والتواجد والخروج") {
                showQuick = true
            }
            Divider().overlay(Color.white.opacity(0.08))
            settingRow(icon: "beach.umbrella.fill", color: Color(hex: 0xFBBF24),
                       title: "وضع الإجازة",
                       subtitle: store.isOnVacation ? "مفعّل الآن" : "إيقاف التذكيرات مؤقتاً") {
                showVacation = true
            }
        }
        .card(padding: 6)
    }

    private var notificationsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "bell.fill", color: Color(hex: 0x34D399),
                       title: "تجربة إشعار", subtitle: "يصلك بعد ٥ ثواني مع الأزرار") {
                store.sendTest()
            }
            Divider().overlay(Color.white.opacity(0.08))
            settingRow(icon: "gearshape.fill", color: Color.gray,
                       title: "إعدادات الإشعارات",
                       subtitle: store.permissionDenied ? "مغلقة – اضغط لتفعيلها" : "فتح إعدادات الآيفون") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .card(padding: 6)
    }

    private var dataCard: some View {
        settingRow(icon: "trash.fill", color: Color(hex: 0xFB7185),
                   title: "مسح السجل", subtitle: "حذف الإحصائيات وسجل البصمات") {
            confirmReset = true
        }
        .card(padding: 6)
    }

    private func settingRow(icon: String, color: Color, title: String, subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button {
            haptic(.light)
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(color.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.muted)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func arNumString(_ s: String) -> String {
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                           "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(s.map { map[$0] ?? $0 })
    }
}
