import SwiftUI
import WidgetKit

private struct TrackerComplicationEntry: TimelineEntry {
    let date: Date
}

private struct TrackerComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrackerComplicationEntry {
        TrackerComplicationEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TrackerComplicationEntry) -> Void) {
        completion(TrackerComplicationEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrackerComplicationEntry>) -> Void) {
        completion(Timeline(entries: [TrackerComplicationEntry(date: Date())], policy: .never))
    }
}

private struct TrackerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLauncherView()
                .containerBackground(.clear, for: .widget)
        case .accessoryCorner:
            CornerLauncherView()
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text("Open Tracker")
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularLauncherView()
                .containerBackground(.clear, for: .widget)
        default:
            CircularLauncherView()
                .containerBackground(.clear, for: .widget)
        }
    }
}

private struct CircularLauncherView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("Open Tracker")
    }
}

private struct CornerLauncherView: View {
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "figure.run")
                .font(.system(size: 16, weight: .semibold))
            Text("TRACK")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
        }
        .widgetAccentable()
        .accessibilityLabel("Open Tracker")
    }
}

private struct RectangularLauncherView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title3.weight(.semibold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text("Tracker")
                    .font(.headline)
                    .lineLimit(1)
                Text("Open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Open Tracker")
    }
}

struct TrackerLauncherComplication: Widget {
    private let kind = "TrackerLauncherComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrackerComplicationProvider()) { entry in
            TrackerComplicationView(entry: entry)
                .widgetURL(URL(string: "tracker://open"))
        }
        .configurationDisplayName("Tracker")
        .description("Open Tracker from your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct TrackerWatchWidgets: WidgetBundle {
    var body: some Widget {
        TrackerLauncherComplication()
    }
}
