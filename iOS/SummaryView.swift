import SwiftUI

private enum SummaryReport: String, CaseIterable, Identifiable, Hashable {
    case overview
    case records

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .records: return "Records"
        }
    }
}

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

private enum SummaryActivityFilter: Hashable, Identifiable {
    case all
    case allRuns
    case allWalks
    case activity(WorkoutActivity)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .allRuns:
            return "all-runs"
        case .allWalks:
            return "all-walks"
        case .activity(let activity):
            return activity.id
        }
    }

    var displayName: String {
        switch self {
        case .all:
            return "All Activities"
        case .allRuns:
            return "All Runs"
        case .allWalks:
            return "All Walks"
        case .activity(let activity):
            return Self.activityName(activity)
        }
    }

    static var pickerOptions: [SummaryActivityFilter] {
        [.all, .allRuns, .allWalks] + WorkoutActivity.allCases.map { .activity($0) }
    }

    func includes(_ activity: WorkoutActivity) -> Bool {
        switch self {
        case .all:
            return true
        case .allRuns:
            return activity == .outdoorRun || activity == .indoorRun
        case .allWalks:
            return activity == .outdoorWalk || activity == .indoorWalk
        case .activity(let selectedActivity):
            return activity == selectedActivity
        }
    }

    private static func activityName(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .weights:
            return activity.displayName
        default:
            return "\(activity.environment.displayName) \(activity.displayName)"
        }
    }
}

private struct SummaryRefreshKey: Hashable {
    var report: SummaryReport
    var rangePreset: SummaryRangePreset
    var activityFilter: SummaryActivityFilter
    var intervalStart: Date
    var intervalEnd: Date
    var appRevision: Int
}

private struct SummaryComputationInput {
    var workouts: [WorkoutSummary]
    var activityEdits: [ActivityEdit]
    var heartRateSettings: HeartRateSettings
    var userMetrics: UserMetrics
    var interval: DateInterval
    var activityFilter: SummaryActivityFilter
    var excludedBestEffortWorkoutIDs: Set<UUID>
    var report: SummaryReport
}

private struct SummarySnapshot {
    var interval: DateInterval
    var summary: WeeklySummary
    var recentWeeks: [WeeklySummary]
    var vo2History: VO2MaxEstimator.HistorySummary?
    var bestEfforts: [BestEffortDistance: BestEffortResult]

    init(input: SummaryComputationInput) {
        let editByWorkoutID = input.activityEdits.reduce(into: [UUID: ActivityEdit]()) { partial, edit in
            partial[edit.workoutID] = edit
        }
        let adjustedWorkouts = input.workouts.map { workout in
            WorkoutEditApplier.adjustedWorkout(
                workout,
                edit: editByWorkoutID[workout.id] ?? ActivityEdit(workoutID: workout.id)
            )
        }
        let filteredWorkouts = adjustedWorkouts.filter { input.activityFilter.includes($0.activity) }
        let recordWorkouts = adjustedWorkouts.filter {
            $0.activity == .outdoorRun &&
                $0.startDate >= input.interval.start &&
                $0.startDate < input.interval.end
        }

        interval = input.interval
        summary = SummaryEngine.summary(
            workouts: filteredWorkouts,
            heartRateSettings: input.heartRateSettings,
            interval: input.interval
        )
        recentWeeks = SummaryEngine.recentWeeklySummaries(
            workouts: filteredWorkouts,
            heartRateSettings: input.heartRateSettings,
            weekCount: 4
        )
        vo2History = VO2MaxEstimator.history(
            workouts: filteredWorkouts,
            userMetrics: input.userMetrics,
            settings: input.heartRateSettings
        )
        bestEfforts = input.report == .records
            ? BestEffortEngine.fastestEfforts(
                workouts: recordWorkouts,
                excluding: input.excludedBestEffortWorkoutIDs
            )
            : [:]
    }
}

struct SummaryView: View {
    @Environment(AppState.self) private var appState
    @State private var report: SummaryReport = .overview
    @State private var rangePreset: SummaryRangePreset = .week
    @State private var activityFilter: SummaryActivityFilter = .all
    @State private var anchorDate = Date()
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var summarySnapshot: SummarySnapshot?
    @State private var isLoadingSummary = false

    var body: some View {
        let refreshKey = summaryRefreshKey

        List {
            Section {
                Picker("Report", selection: $report) {
                    ForEach(SummaryReport.allCases) { report in
                        Text(report.displayName).tag(report)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Range") {
                Picker("Period", selection: $rangePreset) {
                    ForEach(SummaryRangePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                if report == .overview {
                    Picker("Activity", selection: $activityFilter) {
                        ForEach(SummaryActivityFilter.pickerOptions) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

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

            if let summarySnapshot {
                if report == .overview {
                    summarySections(for: summarySnapshot)
                } else {
                    bestEffortSections(for: summarySnapshot)
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ThinkingIndicator()
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .accessibilityLabel("Loading Summary")
                }
            }
        }
        .navigationTitle("Summary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if (isLoadingSummary && summarySnapshot != nil) || (report == .records && isLoadingBestEffortRoutes) {
                    ThinkingIndicator()
                }
            }
        }
        .task(id: refreshKey) {
            await refreshSummary(for: refreshKey)
        }
    }

    @ViewBuilder
    private func bestEffortSections(for snapshot: SummarySnapshot) -> some View {
        Section {
            ForEach(BestEffortDistance.allCases) { distance in
                if let result = snapshot.bestEfforts[distance],
                   let workout = appState.latestWorkout(for: result.workoutID) {
                    NavigationLink {
                        ActivityDetailView(workout: workout, reviewedBestEffort: result)
                    } label: {
                        BestEffortRow(distance: distance, result: result)
                    }
                } else {
                    BestEffortRow(distance: distance, result: nil)
                }
            }

            if isLoadingBestEffortRoutes {
                HStack {
                    Spacer()
                    ThinkingIndicator()
                    Spacer()
                }
                .padding(.vertical, 4)
                .accessibilityLabel("Loading Run Routes")
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Running Best Efforts")
                Text(summaryHeader(for: snapshot.interval))
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func summarySections(for snapshot: SummarySnapshot) -> some View {
        let summary = snapshot.summary
        let recentWeeks = snapshot.recentWeeks
        let vo2History = snapshot.vo2History

        Group {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        SummaryTile(title: "Time", value: WorkoutFormatter.duration(summary.totalTime))
                        SummaryTile(title: "Distance", value: WorkoutFormatter.distance(summary.totalDistanceMeters, unit: appState.settings.distanceUnit))
                    }
                    GridRow {
                        SummaryTile(title: "Workouts", value: "\(summary.workoutCount)")
                        SummaryTile(title: "Active Calories", value: WorkoutFormatter.activeCalories(summary.activeCalories))
                    }
                    GridRow {
                        SummaryTile(title: "Active Days", value: "\(summary.activeDays)")
                        SummaryTile(title: "Avg HR", value: summary.averageHeartRate.map { "\($0)" } ?? "--")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(summaryHeader(for: snapshot.interval))
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
    }

    private var summaryRefreshKey: SummaryRefreshKey {
        let interval = selectedInterval
        return SummaryRefreshKey(
            report: report,
            rangePreset: rangePreset,
            activityFilter: activityFilter,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            appRevision: appState.summaryRevision
        )
    }

    private func refreshSummary(for key: SummaryRefreshKey) async {
        isLoadingSummary = true
        do {
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let input = SummaryComputationInput(
            workouts: appState.workouts,
            activityEdits: appState.activityEdits,
            heartRateSettings: appState.settings.heartRate,
            userMetrics: appState.settings.userMetrics,
            interval: DateInterval(start: key.intervalStart, end: key.intervalEnd),
            activityFilter: key.activityFilter,
            excludedBestEffortWorkoutIDs: appState.excludedBestEffortWorkoutIDs,
            report: key.report
        )

        let snapshot = await Task.detached(priority: .userInitiated) {
            SummarySnapshot(input: input)
        }.value

        guard !Task.isCancelled else { return }
        summarySnapshot = snapshot
        isLoadingSummary = false
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

    private var isLoadingBestEffortRoutes: Bool {
        appState.workouts.contains { workout in
            workout.activity == .outdoorRun &&
                workout.startDate >= selectedInterval.start &&
                workout.startDate < selectedInterval.end &&
                appState.isLoadingDetails(for: workout.id)
        }
    }

    private func summaryHeader(for interval: DateInterval) -> String {
        let dateRange = formattedDateRange(for: interval)
        switch rangePreset {
        case .day:
            return "Day of \(dateRange)"
        case .week:
            return "Week of \(dateRange)"
        case .month:
            return "Month of \(dateRange)"
        case .year:
            return "Year of \(dateRange)"
        case .custom:
            return "Custom \(dateRange)"
        }
    }

    private func formattedDateRange(for interval: DateInterval) -> String {
        SummaryPeriodFormatter.dateRangeText(for: interval)
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

private struct BestEffortRow: View {
    let distance: BestEffortDistance
    let result: BestEffortResult?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(distance.displayName)
                    .font(.headline)
                if let result {
                    Text(result.workoutStartDate, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(result.map { WorkoutFormatter.bestEffortDuration($0.duration) } ?? "--")
                .font(.headline.monospacedDigit())
                .foregroundStyle(result == nil ? .secondary : .primary)
        }
        .padding(.vertical, 2)
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
