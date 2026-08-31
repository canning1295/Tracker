import MapKit
import SwiftUI

struct ActivityDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutSummary
    let onDelete: (UUID) -> Void
    let reviewedBestEffort: BestEffortResult?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        let currentWorkout = appState.latestWorkout(for: workout.id) ?? workout
        let edit = appState.edit(for: currentWorkout.id)
        let displayWorkout = WorkoutEditApplier.adjustedWorkout(currentWorkout, edit: edit)
        let removedPauseSeconds = WorkoutEditApplier.removedPauseSeconds(for: currentWorkout, edit: edit)
        let displaySplits = SplitBuilder.splits(for: displayWorkout, unit: appState.settings.distanceUnit)
        let isLoadingDetails = appState.isLoadingDetails(for: currentWorkout.id)

        List {
            Section {
                metricGrid(workout: displayWorkout, splits: displaySplits)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            if currentWorkout.activity == .outdoorRun {
                Section("Fastest Reports") {
                    if let reviewedBestEffort {
                        LabeledContent(reviewedBestEffort.distance.displayName) {
                            Text(WorkoutFormatter.bestEffortDuration(reviewedBestEffort.duration))
                                .monospacedDigit()
                        }
                        LabeledContent("Segment") {
                            Text(segmentTimeRange(reviewedBestEffort))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Include This Activity", isOn: Binding(
                        get: { appState.isIncludedInBestEfforts(currentWorkout.id) },
                        set: { appState.setBestEffortInclusion($0, for: currentWorkout.id) }
                    ))
                }
            }

            if edit.hasAdjustments {
                Section("App Edits") {
                    LabeledContent("Trimmed") {
                        Text(WorkoutFormatter.duration(edit.trimStartSeconds + edit.trimEndSeconds))
                    }
                    LabeledContent("Removed pauses") {
                        Text(WorkoutFormatter.duration(removedPauseSeconds))
                    }
                    LabeledContent("Adjusted time") {
                        Text(WorkoutFormatter.duration(displayWorkout.duration))
                    }
                }
            }

            if let mergedWorkoutIDs = appState.mergedWorkoutIDs(for: currentWorkout.id) {
                Section("Combined Activity") {
                    LabeledContent("Activities") {
                        Text("\(mergedWorkoutIDs.count)")
                    }
                    Button {
                        appState.unmergeWorkout(currentWorkout.id)
                    } label: {
                        Label("Separate Activities", systemImage: "rectangle.split.2x1")
                    }
                }
            }

            if !displayWorkout.route.isEmpty {
                Section("Route") {
                    RouteMapView(
                        route: displayWorkout.route,
                        highlightedRange: reviewedBestEffort.map { $0.segmentStart...$0.segmentEnd }
                    )
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            let zoneDurations = HeartRateZoneCalculator.zoneDurations(
                samples: displayWorkout.heartRateSamples,
                settings: appState.settings.heartRate,
                workoutEnd: displayWorkout.endDate
            )
            if !zoneDurations.isEmpty {
                Section("Heart Rate Zones") {
                    ForEach(HeartRateZone.allCases) { zone in
                        let duration = zoneDurations[zone] ?? 0
                        if duration > 0 {
                            ZoneDurationRow(zone: zone, duration: duration, total: zoneDurations.values.reduce(0, +))
                        }
                    }
                }
            }

            if !displaySplits.isEmpty {
                Section("Splits") {
                    ForEach(displaySplits.indices, id: \.self) { index in
                        let split = displaySplits[index]
                        HStack {
                            Text("\(index + 1)")
                            Spacer()
                            Text(WorkoutFormatter.distance(split.distanceMeters, unit: appState.settings.distanceUnit))
                            Text(WorkoutFormatter.pace(split.paceSecondsPerUnit, unit: appState.settings.distanceUnit))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Edit") {
                NavigationLink {
                    ActivityEditView(workout: currentWorkout)
                } label: {
                    Label("Trim start/end and remove pauses", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label(isDeleting ? "Deleting Activity" : "Delete Activity", systemImage: "trash")
                }
                .disabled(isDeleting)
            }

            Section("Strava") {
                if currentWorkout.source == .demo {
                    Label("Only Apple Health workouts are uploaded to Strava.", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {
                    let status = appState.stravaStatus(for: currentWorkout.id)
                    HStack {
                        Label(status.displayName, systemImage: "arrow.up.circle")
                        Spacer()
                        if appState.settings.stravaAutoUpload {
                            Text("Auto")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let record = appState.stravaRecord(for: currentWorkout.id) {
                        if let uploadID = record.stravaUploadID, record.status != .uploaded {
                            LabeledContent("Upload ID") {
                                Text(uploadID)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let activityID = record.stravaActivityID {
                            LabeledContent("Activity ID") {
                                Text(activityID)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let error = record.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    if edit.hasAdjustments, status == .uploaded {
                        Text("Local edits do not replace the activity already uploaded to Strava.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if status == .uploaded {
                        Label("Already uploaded", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            appState.retryStravaUpload(workout: currentWorkout)
                        } label: {
                            Label(stravaActionTitle(for: status), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .navigationTitle(displayWorkout.activity.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoadingDetails || isDeleting {
                    ThinkingIndicator()
                }
            }
        }
        .confirmationDialog("Delete Activity?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive) {
                Task { await deleteWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage(for: currentWorkout))
        }
        .alert("Could Not Delete Activity", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    init(
        workout: WorkoutSummary,
        reviewedBestEffort: BestEffortResult? = nil,
        onDelete: @escaping (UUID) -> Void = { _ in }
    ) {
        self.workout = workout
        self.reviewedBestEffort = reviewedBestEffort
        self.onDelete = onDelete
    }

    @MainActor
    private func deleteWorkout() async {
        isDeleting = true
        let deleted = await appState.deleteWorkout(appState.latestWorkout(for: workout.id) ?? workout)
        isDeleting = false
        if deleted {
            onDelete(workout.id)
            dismiss()
        } else {
            deleteError = appState.authorizationMessage ?? "The activity was not deleted."
        }
    }

    private func deleteConfirmationMessage(for workout: WorkoutSummary) -> String {
        if let mergedWorkoutIDs = appState.mergedWorkoutIDs(for: workout.id) {
            return "This removes all \(mergedWorkoutIDs.count) combined activities from Tracker and asks Apple Health to delete the workouts."
        }
        return workout.source == .healthKit
            ? "This removes the activity from Tracker and asks Apple Health to delete the workout."
            : "This removes the activity from Tracker."
    }

    private func metricGrid(workout: WorkoutSummary, splits: [SplitSummary]) -> some View {
        let movingDuration = appState.movingDuration(for: workout)
        // Only worth splitting the two apart once they actually disagree.
        let stoppedSeconds = movingDuration.map { workout.duration - $0 } ?? 0
        let showsMovingTime = stoppedSeconds >= 5

        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                MetricTile(
                    title: showsMovingTime ? "Moving Time" : "Time",
                    value: WorkoutFormatter.duration(showsMovingTime ? (movingDuration ?? workout.duration) : workout.duration)
                )
                if workout.activity.recordsDistance {
                    MetricTile(title: "Distance", value: workout.distanceMeters > 0 ? WorkoutFormatter.distance(workout.distanceMeters, unit: appState.settings.distanceUnit) : "--")
                } else {
                    MetricTile(title: "Active Calories", value: WorkoutFormatter.activeCalories(workout.activeEnergyKilocalories))
                }
            }
            GridRow {
                MetricTile(title: "Avg HR", value: workout.averageHeartRate.map { "\($0)" } ?? "--")
                MetricTile(title: "Max HR", value: workout.maxHeartRate.map { "\($0)" } ?? "--")
            }
            if workout.activity.supportsPace {
                GridRow {
                    MetricTile(title: "Active Calories", value: WorkoutFormatter.activeCalories(workout.activeEnergyKilocalories))
                    MetricTile(title: "Pace", value: WorkoutFormatter.pace(PaceCalculator.averagePaceSecondsPerUnit(for: workout, splits: splits, unit: appState.settings.distanceUnit), unit: appState.settings.distanceUnit))
                }
            }
            if showsMovingTime {
                GridRow {
                    MetricTile(title: "Total Time", value: WorkoutFormatter.duration(workout.duration))
                    MetricTile(title: "Stopped", value: WorkoutFormatter.duration(stoppedSeconds))
                }
            }
            if workout.activity == .outdoorRun || workout.activity == .outdoorWalk {
                GridRow {
                    MetricTile(title: "VO2 Est.", value: vo2Text(for: workout))
                }
            }
        }
    }

    private func vo2Text(for workout: WorkoutSummary) -> String {
        guard let estimate = VO2MaxEstimator.estimate(workout: workout, userMetrics: appState.settings.userMetrics, settings: appState.settings.heartRate) else {
            return "--"
        }
        return String(format: "%.1f", estimate)
    }

    private func segmentTimeRange(_ effort: BestEffortResult) -> String {
        let start = effort.segmentStart.formatted(.dateTime.hour().minute().second())
        let end = effort.segmentEnd.formatted(.dateTime.hour().minute().second())
        return "\(start) - \(end)"
    }

    private func stravaActionTitle(for status: StravaUploadStatus) -> String {
        switch status {
        case .notUploaded:
            return "Upload to Strava"
        case .uploading, .processing:
            return "Check upload status"
        case .pending, .failed:
            return "Retry upload"
        case .uploaded:
            return "Already uploaded"
        }
    }
}

private struct ZoneDurationRow: View {
    let zone: HeartRateZone
    let duration: TimeInterval
    let total: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(zone.displayName, systemImage: "heart.fill")
                    .foregroundStyle(zone.color)
                Spacer()
                Text(WorkoutFormatter.duration(duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let width = total > 0 ? proxy.size.width * min(1, duration / total) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(zone.color).frame(width: width)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

private struct MetricTile: View {
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

private struct RouteMapView: View {
    let route: [RoutePoint]
    var highlightedRange: ClosedRange<Date>?

    var body: some View {
        Map {
            if route.count > 1 {
                if highlightedRange == nil {
                    MapPolyline(coordinates: coordinates(for: route))
                        .stroke(.orange, lineWidth: 4)
                } else {
                    MapPolyline(coordinates: coordinates(for: route))
                        .stroke(.secondary.opacity(0.55), lineWidth: 3)

                    if highlightedRoute.count > 1 {
                        MapPolyline(coordinates: coordinates(for: highlightedRoute))
                            .stroke(.orange, lineWidth: 6)
                    }
                }
            }
            if let last = route.last {
                Annotation("Current", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    Image(systemName: "location.north.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .mapControls {
            MapScaleView()
        }
    }

    private var highlightedRoute: [RoutePoint] {
        guard let highlightedRange else { return [] }
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        let includedIndices = sorted.indices.filter { highlightedRange.contains(sorted[$0].timestamp) }
        let first = includedIndices.first
            ?? sorted.firstIndex { $0.timestamp >= highlightedRange.lowerBound }
            ?? sorted.index(before: sorted.endIndex)
        let last = includedIndices.last
            ?? sorted.lastIndex { $0.timestamp <= highlightedRange.upperBound }
            ?? sorted.startIndex
        let lower = max(sorted.startIndex, min(first, last) - 1)
        let upper = min(sorted.index(before: sorted.endIndex), max(first, last) + 1)
        return Array(sorted[lower...upper])
    }

    private func coordinates(for points: [RoutePoint]) -> [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
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
