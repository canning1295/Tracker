import SwiftUI

struct ActivityEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let workout: WorkoutSummary

    @State private var trimStartSeconds = 0.0
    @State private var trimEndSeconds = 0.0
    @State private var detectedPauses: [DateRangeValue] = []
    @State private var didScanPauses = false

    var body: some View {
        let adjustedWorkout = WorkoutEditApplier.adjustedWorkout(workout, edit: draftEdit)
        let removedPauseSeconds = WorkoutEditApplier.removedPauseSeconds(for: workout, edit: draftEdit)

        Form {
            Section("Trim") {
                DatePicker("Start", selection: startDateBinding, in: startDateRange, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: endDateBinding, in: endDateRange, displayedComponents: [.date, .hourAndMinute])
                LabeledContent("Trimmed") {
                    Text(WorkoutFormatter.duration(trimStartSeconds + trimEndSeconds))
                        .monospacedDigit()
                }
                Button {
                    resetTrim()
                } label: {
                    Label("Reset Trim", systemImage: "arrow.counterclockwise")
                }
                .disabled(trimStartSeconds == 0 && trimEndSeconds == 0)
            }

            Section("Remove Pauses") {
                Button {
                    didScanPauses = true
                    detectedPauses = PauseDetector.candidatePauseRanges(route: workout.route).map {
                        DateRangeValue(start: $0.lowerBound, end: $0.upperBound)
                    }
                } label: {
                    Label("Scan for pauses", systemImage: "pause.circle")
                }
                .disabled(workout.route.isEmpty)

                if workout.route.isEmpty {
                    Label("Pause scan needs GPS route data.", systemImage: "location.slash")
                        .foregroundStyle(.secondary)
                } else if didScanPauses && detectedPauses.isEmpty {
                    Label("No pause candidates found.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                ForEach(detectedPauses) { range in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(WorkoutFormatter.duration(range.duration))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text("\(range.start.formatted(date: .omitted, time: .shortened)) - \(range.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removePause(range)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button(role: .destructive) {
                    detectedPauses = []
                } label: {
                    Label("Clear Pauses", systemImage: "trash")
                }
                .disabled(detectedPauses.isEmpty)
            }

            Section("Adjusted Result") {
                LabeledContent("Start") {
                    Text(adjustedWorkout.startDate.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("End") {
                    Text(adjustedWorkout.endDate.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Time") {
                    Text(WorkoutFormatter.duration(adjustedWorkout.duration))
                        .monospacedDigit()
                }
                if adjustedWorkout.activity.recordsDistance {
                    LabeledContent("Distance") {
                        Text(adjustedWorkout.distanceMeters > 0 ? WorkoutFormatter.distance(adjustedWorkout.distanceMeters, unit: appState.settings.distanceUnit) : "--")
                    }
                } else {
                    LabeledContent("Calories") {
                        Text(WorkoutFormatter.calories(adjustedWorkout.activeEnergyKilocalories))
                    }
                }
                LabeledContent("Removed pauses") {
                    Text(WorkoutFormatter.duration(removedPauseSeconds))
                        .monospacedDigit()
                }
            }

            Section {
                Button {
                    appState.saveEdit(draftEdit)
                    dismiss()
                } label: {
                    Label("Save Edits", systemImage: "checkmark")
                }

                Button(role: .destructive) {
                    resetAllEdits()
                    appState.saveEdit(ActivityEdit(workoutID: workout.id))
                    dismiss()
                } label: {
                    Label("Clear Edits", systemImage: "trash")
                }
                .disabled(!draftEdit.hasAdjustments)
            }
        }
        .navigationTitle("Edit Activity")
        .onAppear {
            let edit = appState.edit(for: workout.id)
            trimStartSeconds = edit.trimStartSeconds
            trimEndSeconds = edit.trimEndSeconds
            detectedPauses = edit.removedPauses
            didScanPauses = !edit.removedPauses.isEmpty
            normalizeTrimValues()
        }
    }

    private var draftEdit: ActivityEdit {
        ActivityEdit(
            workoutID: workout.id,
            trimStartSeconds: trimStartSeconds,
            trimEndSeconds: trimEndSeconds,
            removedPauses: detectedPauses
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding {
            trimmedStartDate
        } set: { newDate in
            let clamped = clampedDate(newDate, lower: workout.startDate, upper: latestStartDate)
            trimStartSeconds = max(0, clamped.timeIntervalSince(workout.startDate))
            normalizeTrimValues()
        }
    }

    private var endDateBinding: Binding<Date> {
        Binding {
            trimmedEndDate
        } set: { newDate in
            let clamped = clampedDate(newDate, lower: earliestEndDate, upper: workout.endDate)
            trimEndSeconds = max(0, workout.endDate.timeIntervalSince(clamped))
            normalizeTrimValues()
        }
    }

    private var startDateRange: ClosedRange<Date> {
        workout.startDate...latestStartDate
    }

    private var endDateRange: ClosedRange<Date> {
        earliestEndDate...workout.endDate
    }

    private var trimmedStartDate: Date {
        workout.startDate.addingTimeInterval(trimStartSeconds)
    }

    private var trimmedEndDate: Date {
        workout.endDate.addingTimeInterval(-trimEndSeconds)
    }

    private var latestStartDate: Date {
        max(workout.startDate, trimmedEndDate.addingTimeInterval(-minimumRetainedDuration))
    }

    private var earliestEndDate: Date {
        min(workout.endDate, trimmedStartDate.addingTimeInterval(minimumRetainedDuration))
    }

    private var minimumRetainedDuration: TimeInterval {
        workout.duration <= 0 ? 0 : min(60, max(1, workout.duration))
    }

    private func normalizeTrimValues() {
        trimStartSeconds = min(max(trimStartSeconds, 0), max(0, workout.duration))
        let maximumEndTrim = max(0, workout.duration - trimStartSeconds - minimumRetainedDuration)
        trimEndSeconds = min(max(trimEndSeconds, 0), maximumEndTrim)
    }

    private func resetTrim() {
        trimStartSeconds = 0
        trimEndSeconds = 0
    }

    private func resetAllEdits() {
        trimStartSeconds = 0
        trimEndSeconds = 0
        detectedPauses = []
        didScanPauses = false
    }

    private func removePause(_ range: DateRangeValue) {
        detectedPauses.removeAll { $0.id == range.id }
    }

    private func clampedDate(_ date: Date, lower: Date, upper: Date) -> Date {
        min(max(date, lower), upper)
    }
}
