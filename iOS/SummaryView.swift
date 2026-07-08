import SwiftUI

private enum SummaryRangePreset: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .custom: return "Custom"
        }
    }
}

struct SummaryView: View {
    @Environment(AppState.self) private var appState
    @State private var rangePreset: SummaryRangePreset = .week
    @State private var anchorDate = Date()
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()

    var body: some View {
        let workouts = appState.adjustedWorkouts
        let interval = selectedInterval
        let summary = SummaryEngine.summary(
            workouts: workouts,
            heartRateSettings: appState.settings.heartRate,
            interval: interval
        )
        let recentWeeks = SummaryEngine.recentWeeklySummaries(workouts: workouts, heartRateSettings: appState.settings.heartRate, weekCount: 4)
        let vo2History = VO2MaxEstimator.history(
            workouts: workouts,
            userMetrics: appState.settings.userMetrics,
            settings: appState.settings.heartRate
        )

        List {
            Section("Range") {
                Picker("Period", selection: $rangePreset) {
                    ForEach(SummaryRangePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                if rangePreset == .custom {
                    DatePicker(selection: $customStart, displayedComponents: .date) {
                        Label("Start", systemImage: "calendar")
                    }
                    DatePicker(selection: $customEnd, displayedComponents: .date) {
                        Label("End", systemImage: "calendar")
                    }
                } else {
                    DatePicker(selection: $anchorDate, displayedComponents: .date) {
                        Label("Date", systemImage: "calendar")
                    }
                }
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        SummaryTile(title: "Time", value: WorkoutFormatter.duration(summary.totalTime))
                        SummaryTile(title: "Distance", value: WorkoutFormatter.distance(summary.totalDistanceMeters, unit: appState.settings.distanceUnit))
                    }
                    GridRow {
                        SummaryTile(title: "Workouts", value: "\(summary.workoutCount)")
                        SummaryTile(title: "Calories", value: WorkoutFormatter.calories(summary.calories))
                    }
                    GridRow {
                        SummaryTile(title: "Active Days", value: "\(summary.activeDays)")
                        SummaryTile(title: "Avg HR", value: summary.averageHeartRate.map { "\($0)" } ?? "--")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(summaryHeader(for: interval))
            }

            if let vo2History {
                Section("VO2 Estimate") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            SummaryTile(title: "Current", value: vo2Value(vo2History.current))
                            SummaryTile(title: "Recent Avg", value: vo2Value(vo2History.recentAverage))
                        }
                        GridRow {
                            SummaryTile(title: "Best", value: vo2Value(vo2History.best))
                            SummaryTile(title: "Trend", value: vo2Trend(vo2History.changeFromPrevious))
                        }
                    }
                    .padding(.vertical, 4)

                    ForEach(vo2History.points.prefix(5)) { point in
                        HStack {
                            Label(point.activity.displayName, systemImage: point.activity.symbolName)
                            Text(point.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(vo2Value(point.estimate))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Recent Weeks") {
                WeeklySummaryLegend()
                ForEach(recentWeeks, id: \.weekStart) { week in
                    WeeklySummaryRow(
                        week: week,
                        maxDistanceMeters: recentWeeks.map(\.totalDistanceMeters).max() ?? 0,
                        maxTime: recentWeeks.map(\.totalTime).max() ?? 0,
                        unit: appState.settings.distanceUnit
                    )
                }
            }

            Section("Distance by Activity") {
                ForEach(WorkoutActivity.allCases) { activity in
                    let meters = summary.distanceByActivity[activity] ?? 0
                    if meters > 0 {
                        HStack {
                            Label(activity.displayName, systemImage: activity.symbolName)
                            Spacer()
                            Text(WorkoutFormatter.distance(meters, unit: appState.settings.distanceUnit))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Time by Activity") {
                ForEach(WorkoutActivity.allCases) { activity in
                    let seconds = summary.timeByActivity[activity] ?? 0
                    if seconds > 0 {
                        HStack {
                            Label(activity.displayName, systemImage: activity.symbolName)
                            Spacer()
                            Text(WorkoutFormatter.duration(seconds))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !summary.heartRateZoneDurations.isEmpty {
                Section("Heart Rate Zones") {
                    ForEach(HeartRateZone.allCases) { zone in
                        let duration = summary.heartRateZoneDurations[zone] ?? 0
                        if duration > 0 {
                            HStack {
                                Label(zone.displayName, systemImage: "heart.fill")
                                    .foregroundStyle(zone.color)
                                Spacer()
                                Text(WorkoutFormatter.duration(duration))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Summary")
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        switch rangePreset {
        case .day:
            return calendar.dateInterval(of: .day, for: anchorDate) ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 86_400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: anchorDate) ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 7 * 86_400)
        case .month:
            return calendar.dateInterval(of: .month, for: anchorDate) ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 30 * 86_400)
        case .year:
            return calendar.dateInterval(of: .year, for: anchorDate) ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 365 * 86_400)
        case .custom:
            let first = min(customStart, customEnd)
            let last = max(customStart, customEnd)
            let start = calendar.startOfDay(for: first)
            let endStart = calendar.startOfDay(for: last)
            let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endStart.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        }
    }

    private func summaryHeader(for interval: DateInterval) -> String {
        let calendar = Calendar.current
        switch rangePreset {
        case .day:
            return anchorDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "Week of \(interval.start.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return anchorDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return anchorDate.formatted(.dateTime.year())
        case .custom:
            let endInclusive = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(endInclusive.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func vo2Value(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func vo2Trend(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))"
    }
}

private struct WeeklySummaryLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            LegendItem(color: .orange, title: "Distance")
            LegendItem(color: .blue, title: "Time")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct WeeklySummaryRow: View {
    let week: WeeklySummary
    let maxDistanceMeters: Double
    let maxTime: TimeInterval
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(week.weekStart, format: .dateTime.month(.abbreviated).day())
                        .font(.headline)
                    Text("\(week.workoutCount) workouts - \(week.activeDays) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(WorkoutFormatter.distance(week.totalDistanceMeters, unit: unit))
                        .font(.subheadline.weight(.semibold))
                    Text(WorkoutFormatter.duration(week.totalTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            WeeklyBarLabel(color: .orange, title: "Distance", value: WorkoutFormatter.distance(week.totalDistanceMeters, unit: unit))
            ProgressBar(value: maxDistanceMeters > 0 ? week.totalDistanceMeters / maxDistanceMeters : 0, color: .orange)
            WeeklyBarLabel(color: .blue, title: "Time", value: WorkoutFormatter.duration(week.totalTime))
            ProgressBar(value: maxTime > 0 ? week.totalTime / maxTime : 0, color: .blue)
        }
        .padding(.vertical, 3)
    }
}

private struct WeeklyBarLabel: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

private extension HeartRateZone {
    var color: Color {
        switch self {
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
