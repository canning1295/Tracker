import SwiftUI

struct ActivityListView: View {
    @Environment(AppState.self) private var appState
    @Binding var activityPath: [WorkoutSummary]
    @State private var showingStartSheet = false

    var body: some View {
        content
            .navigationTitle("Activities")
            .navigationDestination(for: WorkoutSummary.self) { workout in
                ActivityDetailView(workout: workout) { deletedID in
                    activityPath.removeAll { $0.id == deletedID }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingStartSheet = true
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshHealthData() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingStartSheet) {
                StartWorkoutSheet()
            }
            .overlay {
                if appState.isLoadingWorkouts, !appState.visibleWorkouts.isEmpty {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .task {
                await appState.refreshHealthData()
            }
            .onChange(of: appState.visibleWorkouts.map(\.id)) { _, visibleWorkoutIDs in
                let visibleWorkoutIDs = Set(visibleWorkoutIDs)
                activityPath.removeAll { !visibleWorkoutIDs.contains($0.id) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingWorkouts, appState.visibleWorkouts.isEmpty {
            HumorousLoadingView(
                title: "Loading Health data",
                phrases: LoadingPhraseProvider.healthImportPhrases
            )
        } else {
            activityList
        }
    }

    private var activityList: some View {
        List {
            if let message = appState.authorizationMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if appState.visibleWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "figure.run",
                        description: Text("Supported Apple Health workouts will appear here.")
                    )
                } else {
                    ForEach(appState.visibleWorkouts) { workout in
                        let displayWorkout = appState.adjustedWorkout(workout)
                        NavigationLink(value: workout) {
                            ActivityRow(workout: displayWorkout, unit: appState.settings.distanceUnit, stravaStatus: appState.stravaStatus(for: workout.id))
                        }
                    }
                }
            }
        }
    }
}

private struct StartWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section("Outdoor") {
                    ForEach(appState.settings.outdoorOrder) { activity in
                        startButton(for: activity)
                    }
                }

                Section("Indoor") {
                    ForEach(appState.settings.indoorOrder) { activity in
                        startButton(for: activity)
                    }
                }
            }
            .navigationTitle("Start on Watch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startButton(for activity: WorkoutActivity) -> some View {
        Button {
            appState.startOnWatch(activity: activity)
            dismiss()
        } label: {
            Label(activity.displayName, systemImage: activity.symbolName)
        }
    }
}

private struct ActivityRow: View {
    let workout: WorkoutSummary
    let unit: DistanceUnit
    let stravaStatus: StravaUploadStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activity.symbolName)
                .frame(width: 30, height: 30)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activity.displayName)
                    .font(.headline)
                Text(workout.startDate, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(WorkoutFormatter.duration(workout.duration))
                    .font(.subheadline.weight(.semibold))
                if workout.distanceMeters > 0 {
                    Text(WorkoutFormatter.distance(workout.distanceMeters, unit: unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if stravaStatus != .notUploaded {
                    Text(stravaStatus.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
