import MapKit
import SwiftUI

struct ActivityDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutSummary
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        let currentWorkout = appState.latestWorkout(for: workout.id) ?? workout
        let edit = appState.edit(for: currentWorkout.id)
        let displayWorkout = WorkoutEditApplier.adjustedWorkout(currentWorkout, edit: edit)
        let removedPauseSeconds = WorkoutEditApplier.removedPauseSeconds(for: currentWorkout, edit: edit)
        let displaySplits = SplitBuilder.splits(for: displayWorkout, unit: appState.settings.distanceUnit)

        List {
            Section {
                metricGrid(workout: displayWorkout)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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

            if !displayWorkout.route.isEmpty {
                Section("Route") {
                    RouteMapView(route: displayWorkout.route)
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
        .confirmationDialog("Delete Activity?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive) {
                Task { await deleteWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(currentWorkout.source == .healthKit ? "This deletes the workout from Apple Health and removes Tracker edits." : "This removes the activity from Tracker.")
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

    private func deleteWorkout() async {
        isDeleting = true
        let deleted = await appState.deleteWorkout(appState.latestWorkout(for: workout.id) ?? workout)
        isDeleting = false
        if deleted {
            dismiss()
        } else {
            deleteError = appState.authorizationMessage ?? "The activity was not deleted."
        }
    }

    private func metricGrid(workout: WorkoutSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                MetricTile(title: "Time", value: WorkoutFormatter.duration(workout.duration))
                if workout.activity.recordsDistance {
                    MetricTile(title: "Distance", value: workout.distanceMeters > 0 ? WorkoutFormatter.distance(workout.distanceMeters, unit: appState.settings.distanceUnit) : "--")
                } else {
                    MetricTile(title: "Calories", value: WorkoutFormatter.calories(workout.activeEnergyKilocalories))
                }
            }
            GridRow {
                MetricTile(title: "Avg HR", value: workout.averageHeartRate.map { "\($0)" } ?? "--")
                MetricTile(title: "Max HR", value: workout.maxHeartRate.map { "\($0)" } ?? "--")
            }
            if workout.activity.supportsPace {
                GridRow {
                    MetricTile(title: "Calories", value: WorkoutFormatter.calories(workout.activeEnergyKilocalories))
                    MetricTile(title: "Pace", value: WorkoutFormatter.pace(PaceCalculator.paceSecondsPerUnit(distanceMeters: workout.distanceMeters, elapsedSeconds: workout.duration, unit: appState.settings.distanceUnit), unit: appState.settings.distanceUnit))
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

    var body: some View {
        Map {
            if route.count > 1 {
                MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.orange, lineWidth: 4)
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
