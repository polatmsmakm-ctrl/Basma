import WidgetKit
import SwiftUI

// MARK: - Entry & provider

struct BasmaEntry: TimelineEntry {
    let date: Date
    let next: WidgetNext?
    let slots: [WidgetSlot]
    let hasData: Bool
}

struct BasmaProvider: TimelineProvider {
    func placeholder(in context: Context) -> BasmaEntry {
        BasmaEntry(
            date: Date(),
            next: WidgetNext(kind: .entry, fire: Date().addingTimeInterval(3600)),
            slots: [
                WidgetSlot(kind: .entry, hour: 7, minute: 0, done: true),
                WidgetSlot(kind: .presence, hour: 10, minute: 0, done: false),
                WidgetSlot(kind: .exit, hour: 13, minute: 30, done: false)
            ],
            hasData: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BasmaEntry) -> Void) {
        completion(makeEntry(Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BasmaEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now)
        var refresh = now.addingTimeInterval(15 * 60)
        if let n = entry.next, n.fire.addingTimeInterval(60) < refresh {
            refresh = n.fire.addingTimeInterval(60)
        }
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry(_ now: Date) -> BasmaEntry {
        guard let snap = SharedStore.read() else {
            return BasmaEntry(date: now, next: nil, slots: [], hasData: false)
        }
        return BasmaEntry(date: now,
                          next: WidgetLogic.next(snap, now: now),
                          slots: WidgetLogic.today(snap, now: now),
                          hasData: true)
    }
}

// MARK: - Helpers

private let bgTop = Color(hex: 0x0B1020)
private let bgBottom = Color(hex: 0x241C5A)
private let muted = Color.white.opacity(0.65)

private func timeText(_ h: Int, _ m: Int) -> String {
    var comps = DateComponents()
    comps.hour = h
    comps.minute = m
    let date = Calendar.current.date(from: comps) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "ar")
    f.timeStyle = .short
    return f.string(from: date)
}

private func fireText(_ date: Date) -> String {
    let cal = Calendar.current
    let f = DateFormatter()
    f.locale = Locale(identifier: "ar")
    f.timeStyle = .short
    let time = f.string(from: date)
    if cal.isDateInToday(date) { return time }
    if cal.isDateInTomorrow(date) { return "غداً \(time)" }
    let d = DateFormatter()
    d.locale = Locale(identifier: "ar")
    d.dateFormat = "EEEE"
    return "\(d.string(from: date)) \(time)"
}

extension View {
    @ViewBuilder
    func basmaBackground(accessory: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                if accessory {
                    Color.clear
                } else {
                    LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
                }
            }
        } else {
            if accessory {
                self
            } else {
                self.background(LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

// MARK: - Views

struct BasmaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BasmaEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryView
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .basmaBackground(accessory: family == .accessoryRectangular)
    }

    // Small
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.hasData {
                emptyState("افتح «بصمتي» لمزامنة الويدجت")
            } else if let n = entry.next {
                HStack(spacing: 6) {
                    Image(systemName: "touchid")
                        .foregroundColor(n.kind.tint)
                    Text("البصمة القادمة")
                        .font(.caption2)
                        .foregroundColor(muted)
                }
                Spacer(minLength: 0)
                Text(n.kind.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(fireText(n.fire))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(n.kind.tint)
                Text(n.fire, style: .relative)
                    .font(.caption)
                    .foregroundColor(muted)
                    .lineLimit(1)
            } else {
                emptyState("لا توجد بصمات قادمة")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Medium
    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView
            if entry.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("بصمات اليوم")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(muted)
                    if entry.slots.isEmpty {
                        Text("لا توجد بصمات اليوم")
                            .font(.footnote)
                            .foregroundColor(muted)
                    } else {
                        ForEach(entry.slots) { slot in
                            HStack(spacing: 8) {
                                Image(systemName: slot.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(slot.done ? slot.kind.tint : Color.white.opacity(0.35))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(slot.kind.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(slot.done ? muted : .white)
                                        .strikethrough(slot.done)
                                    Text(timeText(slot.hour, slot.minute))
                                        .font(.caption2)
                                        .foregroundColor(muted)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Lock screen
    private var accessoryView: some View {
        HStack(spacing: 8) {
            Image(systemName: "touchid")
                .font(.title3)
            if let n = entry.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.kind.title)
                        .font(.headline)
                    Text(fireText(n.fire))
                        .font(.caption)
                    Text(n.fire, style: .relative)
                        .font(.caption2)
                        .lineLimit(1)
                }
            } else {
                Text(entry.hasData ? "لا بصمات قادمة" : "افتح بصمتي")
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "touchid")
                .font(.title2)
                .foregroundColor(Color(hex: 0x7C83FF))
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Widget & bundle

struct BasmaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BasmaWidget", provider: BasmaProvider()) { entry in
            BasmaWidgetView(entry: entry)
        }
        .configurationDisplayName("بصمتي")
        .description("البصمة القادمة وحالة بصمات اليوم.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct BasmaWidgetBundle: WidgetBundle {
    var body: some Widget {
        BasmaWidget()
        if #available(iOS 26.0, *) {
            BasmaAlarmLiveActivity()
        }
    }
}
