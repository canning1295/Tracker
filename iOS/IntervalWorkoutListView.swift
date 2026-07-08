import SwiftUI

struct IntervalWorkoutListView: View {
    @Environment(AppState.self) private var appState
    @State private var editor: IntervalEditorPresentation?

    var body: some View {
        Group {
            if appState.intervals.isEmpty {
                ContentUnavailableView {
                    Label("No Workouts", systemImage: "timer")
                } actions: {
                    Button {
                        editor = IntervalEditorPresentation(workout: nil)
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(appState.intervals) { workout in
                            Button {
                                editor = IntervalEditorPresentation(workout: workout)
                            } label: {
                                IntervalWorkoutRow(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: appState.deleteIntervals)
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = IntervalEditorPresentation(workout: nil)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { presentation in
            IntervalWorkoutBuilderView(existingWorkout: presentation.workout)
        }
    }
}

private struct IntervalEditorPresentation: Identifiable {
    let id = UUID()
    var workout: IntervalWorkout?
}

private struct IntervalWorkoutRow: View {
    let workout: IntervalWorkout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.name)
                    .font(.headline)
                Text("\(workout.repeats)x \(WorkoutFormatter.duration(TimeInterval(workout.work.durationSeconds))) \(workout.work.label) / \(WorkoutFormatter.duration(TimeInterval(workout.recovery.durationSeconds))) \(workout.recovery.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Total \(WorkoutFormatter.duration(TimeInterval(workout.totalSeconds)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct IntervalWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    private let existingWorkout: IntervalWorkout?

    @State private var draft: IntervalWorkoutDraft

    init(existingWorkout: IntervalWorkout? = nil) {
        self.existingWorkout = existingWorkout
        _draft = State(initialValue: existingWorkout.map(IntervalWorkoutDraft.init(workout:)) ?? IntervalWorkoutDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Workout name", text: $draft.name)
                }

                Section("Structure") {
                    Stepper("Warmup \(draft.warmupMinutes) min", value: $draft.warmupMinutes, in: 0...60)
                    Stepper("Repeats \(draft.repeats)", value: $draft.repeats, in: 1...30)
                    Stepper("Cooldown \(draft.cooldownMinutes) min", value: $draft.cooldownMinutes, in: 0...60)
                }

                Section("Work") {
                    TextField("Label", text: $draft.workLabel)
                    Stepper("Duration \(WorkoutFormatter.duration(TimeInterval(draft.workSeconds)))", value: $draft.workSeconds, in: 15...1800, step: 15)
                    Picker("Intensity", selection: $draft.workIntensity) {
                        ForEach(IntervalIntensity.allCases) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                }

                Section("Recovery") {
                    TextField("Label", text: $draft.recoveryLabel)
                    Stepper("Duration \(WorkoutFormatter.duration(TimeInterval(draft.recoverySeconds)))", value: $draft.recoverySeconds, in: 15...1800, step: 15)
                    Picker("Intensity", selection: $draft.recoveryIntensity) {
                        ForEach(IntervalIntensity.allCases) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                }

                Section("Preview") {
                    LabeledContent("Total") {
                        Text(WorkoutFormatter.duration(TimeInterval(draft.totalSeconds)))
                            .monospacedDigit()
                    }
                    LabeledContent("Repeats") {
                        Text("\(draft.normalizedRepeats)x \(draft.normalizedWorkLabel) / \(draft.normalizedRecoveryLabel)")
                    }
                }
            }
            .navigationTitle(existingWorkout == nil ? "New Workout" : "Edit Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let workout = draft.workout(
                            id: existingWorkout?.id ?? UUID(),
                            workID: existingWorkout?.work.id ?? UUID(),
                            recoveryID: existingWorkout?.recovery.id ?? UUID()
                        ) else { return }
                        appState.saveInterval(workout)
                        dismiss()
                    }
                    .disabled(!draft.canBuildWorkout)
                }
            }
        }
    }
}
