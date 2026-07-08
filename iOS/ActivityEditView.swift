import MapKit
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
                if workout.route.count > 1 {
                    TrimRoutePreviewMap(
                        route: workout.route,
                        keptStart: trimmedStartDate,
                        keptEnd: trimmedEndDate
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    TrimRouteLegend()
                }

                TrimRangeSlider(
                    trimStartSeconds: $trimStartSeconds,
                    trimEndSeconds: $trimEndSeconds,
                    duration: workout.duration,
                    minimumRetainedDuration: minimumRetainedDuration,
                    step: trimStepSeconds
                )
                .padding(.vertical, 8)

                DatePicker("Start time", selection: startDateBinding, in: startDateRange, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Stop time", selection: endDateBinding, in: endDateRange, displayedComponents: [.date, .hourAndMinute])

                TrimFineTuneRow(
                    title: "Start second",
                    timeText: preciseTimeText(for: trimmedStartDate),
                    canMoveEarlier: canNudgeStartEarlier,
                    canMoveLater: canNudgeStartLater,
                    moveEarlier: { nudgeStartTime(by: -fineTuneStepSeconds) },
                    moveLater: { nudgeStartTime(by: fineTuneStepSeconds) }
                )

                TrimFineTuneRow(
                    title: "Stop second",
                    timeText: preciseTimeText(for: trimmedEndDate),
                    canMoveEarlier: canNudgeStopEarlier,
                    canMoveLater: canNudgeStopLater,
                    moveEarlier: { nudgeStopTime(by: -fineTuneStepSeconds) },
                    moveLater: { nudgeStopTime(by: fineTuneStepSeconds) }
                )

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

    private var trimStepSeconds: TimeInterval {
        if workout.duration >= 7_200 {
            return 60
        }
        if workout.duration >= 1_800 {
            return 30
        }
        if workout.duration >= 600 {
            return 10
        }
        return 1
    }

    private var fineTuneStepSeconds: TimeInterval {
        1
    }

    private var maximumStartTrim: TimeInterval {
        max(0, workout.duration - trimEndSeconds - minimumRetainedDuration)
    }

    private var maximumEndTrim: TimeInterval {
        max(0, workout.duration - trimStartSeconds - minimumRetainedDuration)
    }

    private var canNudgeStartEarlier: Bool {
        trimStartSeconds > 0
    }

    private var canNudgeStartLater: Bool {
        trimStartSeconds < maximumStartTrim
    }

    private var canNudgeStopEarlier: Bool {
        trimEndSeconds < maximumEndTrim
    }

    private var canNudgeStopLater: Bool {
        trimEndSeconds > 0
    }

    private func normalizeTrimValues() {
        trimStartSeconds = min(max(trimStartSeconds, 0), max(0, workout.duration))
        let maximumEndTrim = max(0, workout.duration - trimStartSeconds - minimumRetainedDuration)
        trimEndSeconds = min(max(trimEndSeconds, 0), maximumEndTrim)
    }

    private func nudgeStartTime(by seconds: TimeInterval) {
        trimStartSeconds = min(max(trimStartSeconds + seconds, 0), maximumStartTrim)
        normalizeTrimValues()
    }

    private func nudgeStopTime(by seconds: TimeInterval) {
        trimEndSeconds = min(max(trimEndSeconds - seconds, 0), maximumEndTrim)
        normalizeTrimValues()
    }

    private func preciseTimeText(for date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
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

private struct TrimFineTuneRow: View {
    let title: String
    let timeText: String
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                moveEarlier()
            } label: {
                Label("Earlier", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canMoveEarlier)
            .accessibilityLabel("\(title) earlier")

            Button {
                moveLater()
            } label: {
                Label("Later", systemImage: "plus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canMoveLater)
            .accessibilityLabel("\(title) later")
        }
    }
}

private struct TrimRangeSlider: View {
    @Binding var trimStartSeconds: TimeInterval
    @Binding var trimEndSeconds: TimeInterval
    let duration: TimeInterval
    let minimumRetainedDuration: TimeInterval
    let step: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let handleSize = 34.0
                let handleRadius = handleSize / 2
                let trackWidth = max(proxy.size.width - handleSize, 1)
                let trackStartX = handleRadius
                let trackEndX = trackStartX + trackWidth
                let startX = trackStartX + xPosition(for: trimStartSeconds, width: trackWidth)
                let stopOffset = max(0, duration - trimEndSeconds)
                let stopX = trackStartX + xPosition(for: stopOffset, width: trackWidth)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: trackWidth, height: 8)
                        .offset(x: trackStartX)

                    Capsule()
                        .fill(.red.opacity(0.45))
                        .frame(width: max(0, startX - trackStartX), height: 8)
                        .offset(x: trackStartX)

                    Capsule()
                        .fill(.red.opacity(0.45))
                        .frame(width: max(0, trackEndX - stopX), height: 8)
                        .offset(x: stopX)

                    Capsule()
                        .fill(.orange)
                        .frame(width: max(0, stopX - startX), height: 8)
                        .offset(x: startX)

                    sliderHandle(systemImage: "arrow.right")
                        .frame(width: handleSize, height: handleSize)
                        .position(x: startX, y: 22)
                        .gesture(startDrag(width: trackWidth, originX: trackStartX))
                        .accessibilityLabel("Start trim")
                        .accessibilityValue(WorkoutFormatter.duration(trimStartSeconds))
                        .accessibilityAdjustableAction { direction in
                            adjustStart(direction: direction)
                        }

                    sliderHandle(systemImage: "arrow.left")
                        .frame(width: handleSize, height: handleSize)
                        .position(x: stopX, y: 22)
                        .gesture(stopDrag(width: trackWidth, originX: trackStartX))
                        .accessibilityLabel("Stop trim")
                        .accessibilityValue(WorkoutFormatter.duration(trimEndSeconds))
                        .accessibilityAdjustableAction { direction in
                            adjustStop(direction: direction)
                        }
                }
                .frame(height: 44)
                .coordinateSpace(name: "TrimRangeSliderTrack")
            }
            .frame(height: 44)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cut from start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(WorkoutFormatter.duration(trimStartSeconds))
                        .font(.subheadline.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .center, spacing: 3) {
                    Text("Kept")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(WorkoutFormatter.duration(keptDuration))
                        .font(.subheadline.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Cut from stop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(WorkoutFormatter.duration(trimEndSeconds))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
    }

    private var keptDuration: TimeInterval {
        max(0, duration - trimStartSeconds - trimEndSeconds)
    }

    private func sliderHandle(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(.background)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
            Circle()
                .strokeBorder(.orange, lineWidth: 3)
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        }
        .contentShape(Circle())
    }

    private func startDrag(width: CGFloat, originX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("TrimRangeSliderTrack"))
            .onChanged { value in
                updateStart(x: value.location.x, width: width, originX: originX)
            }
    }

    private func stopDrag(width: CGFloat, originX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("TrimRangeSliderTrack"))
            .onChanged { value in
                updateStop(x: value.location.x, width: width, originX: originX)
            }
    }

    private func updateStart(x: CGFloat, width: CGFloat, originX: CGFloat) {
        guard duration > 0 else {
            trimStartSeconds = 0
            return
        }

        let stopOffset = max(0, duration - trimEndSeconds)
        let latestStart = max(0, stopOffset - minimumRetainedDuration)
        let rawStart = min(max(seconds(for: x, width: width, originX: originX), 0), latestStart)
        trimStartSeconds = min(max(roundedSeconds(rawStart), 0), latestStart)
    }

    private func updateStop(x: CGFloat, width: CGFloat, originX: CGFloat) {
        guard duration > 0 else {
            trimEndSeconds = 0
            return
        }

        let earliestStop = min(duration, trimStartSeconds + minimumRetainedDuration)
        let rawStop = min(max(seconds(for: x, width: width, originX: originX), earliestStop), duration)
        let stopOffset = min(max(roundedSeconds(rawStop), earliestStop), duration)
        trimEndSeconds = max(0, duration - stopOffset)
    }

    private func adjustStart(direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            trimStartSeconds = min(max(0, duration - trimEndSeconds - minimumRetainedDuration), trimStartSeconds + step)
        case .decrement:
            trimStartSeconds = max(0, trimStartSeconds - step)
        @unknown default:
            break
        }
    }

    private func adjustStop(direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            trimEndSeconds = max(0, trimEndSeconds - step)
        case .decrement:
            trimEndSeconds = min(max(0, duration - trimStartSeconds - minimumRetainedDuration), trimEndSeconds + step)
        @unknown default:
            break
        }
    }

    private func xPosition(for seconds: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return width * min(max(seconds / duration, 0), 1)
    }

    private func seconds(for x: CGFloat, width: CGFloat, originX: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return duration * min(max(Double((x - originX) / width), 0), 1)
    }

    private func roundedSeconds(_ seconds: TimeInterval) -> TimeInterval {
        guard step > 0 else { return seconds }
        return (seconds / step).rounded() * step
    }
}

private struct TrimRoutePreviewMap: View {
    let route: [RoutePoint]
    let keptStart: Date
    let keptEnd: Date

    private var sortedRoute: [RoutePoint] {
        route.sorted { $0.timestamp < $1.timestamp }
    }

    private var startCutRoute: [RoutePoint] {
        segment(until: keptStart)
    }

    private var keptRoute: [RoutePoint] {
        segment(from: keptStart, until: keptEnd)
    }

    private var stopCutRoute: [RoutePoint] {
        segment(from: keptEnd)
    }

    var body: some View {
        Map {
            if sortedRoute.count > 1 {
                mapPolyline(for: sortedRoute)
                    .stroke(.gray.opacity(0.28), lineWidth: 8)
            }

            if startCutRoute.count > 1 {
                mapPolyline(for: startCutRoute)
                    .stroke(.red.opacity(0.78), lineWidth: 5)
            }

            if stopCutRoute.count > 1 {
                mapPolyline(for: stopCutRoute)
                    .stroke(.red.opacity(0.78), lineWidth: 5)
            }

            if keptRoute.count > 1 {
                mapPolyline(for: keptRoute)
                    .stroke(.orange, lineWidth: 5)
            }

            if let point = keptRoute.first {
                Annotation("Start", coordinate: coordinate(for: point)) {
                    trimMarker(systemImage: "flag.fill", color: .green)
                }
            }

            if let point = keptRoute.last {
                Annotation("Stop", coordinate: coordinate(for: point)) {
                    trimMarker(systemImage: "flag.checkered", color: .blue)
                }
            }
        }
        .mapControls {
            MapScaleView()
        }
    }

    private func mapPolyline(for points: [RoutePoint]) -> MapPolyline {
        MapPolyline(coordinates: points.map(coordinate(for:)))
    }

    private func trimMarker(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .padding(6)
            .foregroundStyle(.white)
            .background(color, in: Circle())
    }

    private func segment(from lowerBound: Date? = nil, until upperBound: Date? = nil) -> [RoutePoint] {
        let route = sortedRoute
        var segment = route.filter { point in
            if let lowerBound, point.timestamp < lowerBound {
                return false
            }
            if let upperBound, point.timestamp > upperBound {
                return false
            }
            return true
        }

        if let lowerBound,
           let boundary = interpolatedPoint(at: lowerBound),
           segment.first?.timestamp != boundary.timestamp {
            segment.insert(boundary, at: 0)
        }

        if let upperBound,
           let boundary = interpolatedPoint(at: upperBound),
           segment.last?.timestamp != boundary.timestamp {
            segment.append(boundary)
        }

        return segment.sorted { $0.timestamp < $1.timestamp }
    }

    private func interpolatedPoint(at date: Date) -> RoutePoint? {
        let route = sortedRoute
        guard let first = route.first, let last = route.last else { return nil }

        if date <= first.timestamp {
            return first
        }
        if date >= last.timestamp {
            return last
        }
        if let exact = route.first(where: { $0.timestamp == date }) {
            return exact
        }
        guard let nextIndex = route.firstIndex(where: { $0.timestamp > date }), nextIndex > route.startIndex else {
            return nil
        }

        let previous = route[route.index(before: nextIndex)]
        let next = route[nextIndex]
        let interval = next.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return previous }

        let fraction = date.timeIntervalSince(previous.timestamp) / interval
        return RoutePoint(
            latitude: interpolate(previous.latitude, next.latitude, fraction: fraction),
            longitude: interpolate(previous.longitude, next.longitude, fraction: fraction),
            altitudeMeters: interpolate(previous.altitudeMeters, next.altitudeMeters, fraction: fraction),
            timestamp: date,
            horizontalAccuracy: interpolate(previous.horizontalAccuracy, next.horizontalAccuracy, fraction: fraction)
        )
    }

    private func interpolate(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * min(max(fraction, 0), 1)
    }

    private func interpolate(_ start: Double?, _ end: Double?, fraction: Double) -> Double? {
        guard let start, let end else { return start ?? end }
        return interpolate(start, end, fraction: fraction)
    }

    private func coordinate(for point: RoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

private struct TrimRouteLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .orange, text: "Kept route")
            legendItem(color: .red, text: "Cut off")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 24, height: 5)
            Text(text)
        }
    }
}
