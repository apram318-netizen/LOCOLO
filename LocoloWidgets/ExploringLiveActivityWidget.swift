//
//  ExploringLiveActivityWidget.swift
//  LocoloWidgets
//
//  Live Activity / Dynamic Island UI for ExploringAttributes.
//
//  SETUP (owner, Xcode — cannot finish from CLI alone):
//  1. File → New → Target → Widget Extension → name `LocoloWidgets`.
//  2. Enable Live Activities on the app target (NSSupportsLiveActivities=YES — already set).
//  3. Add this file + a shared copy of `ExploringAttributes` (from
//     `Locolo/ARModule/Services/ExploringLiveActivity.swift`) to the widget target
//     (or extract Attributes into a shared framework).
//  4. Delete the template @main widget if it conflicts; keep one @main entry.
//
//  The app already starts/updates/ends activities via ExploringLiveActivity
//  when the AR viewer is open.
//

#if LOCOLO_WIDGETS_TARGET
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LocoloWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExploringLiveActivityWidget()
    }
}

struct ExploringLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExploringAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "arkit")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exploring AR")
                        .font(.headline)
                    if let name = context.state.nearestName,
                       let m = context.state.nearestMeters {
                        Text("\(name) · \(Int(m)) m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(context.state.nearbyCount) nearby")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(context.state.nearbyCount)")
                    .font(.title.weight(.bold))
                    .monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.75))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arkit")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.nearestName ?? "Exploring")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.nearbyCount)")
                        .font(.title3.weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let m = context.state.nearestMeters {
                        Text("Nearest \(Int(m)) m away")
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "arkit")
            } compactTrailing: {
                Text("\(context.state.nearbyCount)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "arkit")
            }
        }
    }
}
#endif
