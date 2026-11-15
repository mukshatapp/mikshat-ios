import SwiftUI
import WidgetKit

struct TrackRecordingLiveActivityConfiguration: Widget {
  @Environment(\.colorScheme) private var colorScheme

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TrackRecordingLiveActivityAttributes.self) { context in
      TrackRecordingLiveActivityView(state: context.state)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          AppLogo()
            .frame(width: 28, height: 28)
        }
        DynamicIslandExpandedRegion(.center) {
          HStack(spacing: 16) {
            StatisticValueView(context.state.duration.value)
            StatisticValueView(context.state.distance.value)
          }
        }
      } compactLeading: {
        AppLogo()
          .frame(width: 20, height: 20)
      } compactTrailing: {
        StatisticValueView(context.state.duration.value)
      } minimal: {
        AppLogo()
          .frame(width: 20, height: 20)
      }
    }
  }
}
