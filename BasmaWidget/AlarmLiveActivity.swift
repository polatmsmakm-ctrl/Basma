import WidgetKit
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit

/// AlarmKit needs a Live Activity so the system can show the alarm on the lock screen / Dynamic Island.
@available(iOS 26.0, *)
struct BasmaAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<BasmaAlarmData>.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "touchid")
                    .font(.title2)
                Text(context.attributes.metadata?.title ?? "بصمتي")
                    .font(.headline)
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.title ?? "بصمتي")
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "touchid")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "touchid")
            }
        }
    }
}
#else
// Older SDK: provide an empty stand-in so the bundle still compiles.
struct BasmaAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BasmaNoop", provider: BasmaProvider()) { _ in EmptyView() }
    }
}
#endif
