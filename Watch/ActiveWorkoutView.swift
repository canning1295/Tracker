import MapKit
import SwiftUI
import WatchKit

private enum WorkoutEndPrompt: Equatable {
    case confirmation
    case trim(WorkoutEndTrimSuggestion)
}

struct ActiveWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var watchState: WatchAppState
    @State private var page = 0
    @State private var endPrompt: WorkoutEndPrompt?
    @State private var resumesAfterEndCancel = false

    var body: some View {
        ZStack {
            TabView(selection: $page) {
                NowPlayingView()
                    .tag(-1)

                WatchMetricsPage(
                    activity: workoutManager.activity,
                    snapshot: workoutManager.snapshot,
                    settings: watchState.settings,
                    isPaused: workoutManager.isPaused,
                    isFinishing: workoutManager.isFinishing,
                    interval: workoutManager.currentInterval
                )
                    .tag(0)

                if hasOutdoorMap {
                    WatchMapPage(snapshot: workoutManager.snapshot, settings: watchState.settings, isPaused: workoutManager.isPaused)
                        .tag(1)
                }

                WatchControlsPage(
                    onPauseResume: togglePause,
                    onRequestEnd: requestEndConfirmation
                )
                    .tag(controlsTag)
            }

            if let endPrompt {
                switch endPrompt {
                case .confirmation:
                    WatchEndConfirmationView(
                        onCancel: cancelEndConfirmation,
                        onEnd: confirmEnd
                    )
                case .trim(let suggestion):
                    WatchEndTrimPromptView(
                        suggestion: suggestion,
                        onKeepAll: {
                            self.endPrompt = nil
                            workoutManager.finishEnd()
                        },
                        onTrim: {
                            self.endPrompt = nil
                            workoutManager.finishEnd(trimSuggestion: suggestion)
                        }
                    )
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        ._statusBarHidden(true)
    }

    private var hasOutdoorMap: Bool {
        workoutManager.activity?.environment == .outdoor
    }

    private var controlsTag: Int {
        hasOutdoorMap ? 2 : 1
    }

    private func togglePause() {
        let isResuming = workoutManager.isPaused
        workoutManager.togglePause()
        if isResuming {
            page = 0
        }
    }

    private func confirmEnd() {
        resumesAfterEndCancel = false
        if let suggestion = workoutManager.prepareToEnd() {
            endPrompt = .trim(suggestion)
            WKInterfaceDevice.current().play(.notification)
        } else {
            endPrompt = nil
            workoutManager.finishEnd()
        }
    }

    private func requestEndConfirmation() {
        resumesAfterEndCancel = workoutManager.beginEndConfirmation()
        endPrompt = .confirmation
    }

    private func cancelEndConfirmation() {
        endPrompt = nil
        workoutManager.cancelEndConfirmation(resumeWorkout: resumesAfterEndCancel)
        if resumesAfterEndCancel {
            page = 0
        }
        resumesAfterEndCancel = false
    }
}

struct WatchWorkoutSummaryView: View {
    let summary: WatchWorkoutCompletionSummary
    let settings: WorkoutSettings
    let onDismiss: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 7) {
                statusSymbol

                Text(statusTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(summary.activity?.displayName ?? "Workout")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .failed(let message) = summary.saveState {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    WatchSummaryMetric(title: "Time", value: WorkoutFormatter.duration(summary.elapsedSeconds), color: .blue)
                    WatchSummaryMetric(title: "Act Cal", value: WorkoutFormatter.activeCalories(summary.activeEnergyKilocalories), color: .pink)

                    if summary.activity?.recordsDistance == true {
                        WatchSummaryMetric(
                            title: summary.distanceIsEstimated ? "Est Distance" : "Distance",
                            value: WorkoutFormatter.distance(summary.distanceMeters, unit: settings.distanceUnit),
                            color: .cyan
                        )
                        WatchSummaryMetric(
                            title: summary.distanceIsEstimated ? "Est Pace" : "Pace",
                            value: WorkoutFormatter.pace(summaryPace, unit: settings.distanceUnit),
                            color: .purple
                        )
                    }
                }

                Button(action: onDismiss) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(summary.saveState == .saving)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .focusable(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        ._statusBarHidden(true)
        .accessibilityAddTraits(.isModal)
    }

    private var summaryPace: Double? {
        PaceCalculator.paceSecondsPerUnit(
            distanceMeters: summary.distanceMeters,
            elapsedSeconds: summary.elapsedSeconds,
            unit: settings.distanceUnit
        )
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch summary.saveState {
        case .saving:
            ProgressView()
                .controlSize(.small)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
    }

    private var statusTitle: String {
        switch summary.saveState {
        case .saving: return "Saving Workout"
        case .saved: return "Workout Saved"
        case .failed: return "Save Failed"
        }
    }
}

private struct WatchSummaryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 43)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        }
    }
}

struct WatchMetricsPage: View {
    let activity: WorkoutActivity?
    let snapshot: WorkoutMetricSnapshot
    let settings: WorkoutSettings
    let isPaused: Bool
    let isFinishing: Bool
    let interval: IntervalWorkout?

    var body: some View {
        let controls = WorkoutControlPresentation(isPaused: isPaused, isFinishing: isFinishing)
        let compactLayout = interval != nil
        let rowSpacing: CGFloat = compactLayout ? 5 : 6
        let metricHeight: CGFloat = compactLayout ? 37 : 47

        VStack(spacing: 3) {
            clockHeader(controls: controls, compactLayout: compactLayout)
                .offset(y: -6)

            if let interval {
                WatchIntervalProgressPanel(progress: IntervalTimeline.progress(for: interval, elapsedSeconds: snapshot.elapsedSeconds))
            }

            if showsDistanceAndPace {
                HStack(spacing: rowSpacing) {
                    MetricBlock(title: "HR", value: heartRateDisplay.valueText, color: heartRateDisplay.color, minHeight: metricHeight)
                    MetricBlock(
                        title: snapshot.distanceIsEstimated ? "Est Dist" : "Distance",
                        value: WorkoutFormatter.distance(snapshot.distanceMeters, unit: settings.distanceUnit),
                        color: .cyan,
                        minHeight: metricHeight
                    )
                }

                HStack(spacing: rowSpacing) {
                    MetricBlock(
                        title: snapshot.distanceIsEstimated ? "Est Pace" : "Pace",
                        value: WorkoutFormatter.pace(snapshot.paceSecondsPerUnit, unit: settings.distanceUnit),
                        color: .purple,
                        minHeight: metricHeight
                    )
                    MetricBlock(title: "Act Cal", value: activeCaloriesText, color: .pink, minHeight: metricHeight)
                }
            } else {
                HStack(spacing: rowSpacing) {
                    MetricBlock(title: "HR", value: heartRateDisplay.valueText, color: heartRateDisplay.color, minHeight: metricHeight)
                    MetricBlock(title: "Act Cal", value: activeCaloriesText, color: .pink, minHeight: metricHeight)
                }
            }

            Text(WorkoutFormatter.duration(snapshot.elapsedSeconds))
                .font(.system(size: compactLayout ? 23 : 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Workout time")
                .offset(y: 6)
        }
        .padding(.horizontal, 9)
        .padding(.top, 1)
        .padding(.bottom, compactLayout ? 3 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func clockHeader(controls: WorkoutControlPresentation, compactLayout: Bool) -> some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, style: .time)
                    .font(.system(size: compactLayout ? 23 : 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Current time")
            }

            if let statusText = controls.statusText {
                HStack {
                    Spacer()
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isFinishing ? Color.secondary : Color.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .frame(height: compactLayout ? 26 : 30)
    }

    private var activeCaloriesText: String {
        "\(Int(WorkoutCalories.activeKilocalories(fromHealthKitActiveKilocalories: snapshot.activeEnergyKilocalories).rounded()))"
    }

    private var showsDistanceAndPace: Bool {
        activity?.supportsPace ?? true
    }

    private var heartRateDisplay: HeartRateDisplayPresentation {
        HeartRateDisplayPresentation(heartRate: snapshot.heartRate, settings: settings.heartRate)
    }
}

private struct WatchIntervalProgressPanel: View {
    let progress: IntervalProgress

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(progress.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(progress.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            HStack(spacing: 4) {
                Text(progress.isComplete ? "Done" : WorkoutFormatter.duration(progress.remainingInStep))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(progressColor)
                Spacer(minLength: 2)
                Text("\(progress.stepIndex)/\(max(progress.stepCount, 1))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.25))
                    Capsule()
                        .fill(progressColor)
                        .frame(width: proxy.size.width * min(max(progress.fractionComplete, 0), 1))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressColor: Color {
        guard let intensity = progress.intensity else { return .orange }
        switch intensity {
        case .easy: return .green
        case .steady: return .yellow
        case .hard: return .orange
        }
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String
    let color: Color
    var minHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(color.opacity(0.26), lineWidth: 1)
        }
    }
}

struct WatchMapPage: View {
    let snapshot: WorkoutMetricSnapshot
    let settings: WorkoutSettings
    let isPaused: Bool

    @FocusState private var focused: Bool
    @State private var zoomSpan = 0.008
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            map
            VStack {
                Text(isPaused ? "Paused" : "Live route")
                    .font(.caption2)
                    .foregroundStyle(isPaused ? .orange : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial, in: Capsule())
                Spacer()
            }
            cornerMetrics
        }
        .focusable()
        .focused($focused)
        .digitalCrownRotation($zoomSpan, from: 0.002, through: 0.04, by: 0.002, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onTapGesture {
            focused.toggle()
        }
        .onAppear {
            position = .region(region)
        }
        .onChange(of: zoomSpan) { _, _ in
            position = .region(region)
        }
        .onChange(of: snapshot.route) { _, _ in
            position = .region(region)
        }
    }

    private var map: some View {
        Map(position: $position, interactionModes: focused ? [.zoom, .pan] : []) {
            if routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.cyan, lineWidth: 4)
            }

            if let currentCoordinate {
                Annotation("Current", coordinate: currentCoordinate) {
                    Image(systemName: "location.north.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(snapshot.headingDegrees ?? 0))
                        .shadow(radius: 2)
                }
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cornerMetrics: some View {
        VStack {
            HStack {
                cornerText(WorkoutFormatter.distance(snapshot.distanceMeters, unit: settings.distanceUnit))
                Spacer()
                cornerText(WorkoutFormatter.duration(snapshot.elapsedSeconds))
            }
            Spacer()
            HStack {
                cornerHeart(heartRateDisplay)
                Spacer()
                cornerText(WorkoutFormatter.pace(snapshot.paceSecondsPerUnit, unit: settings.distanceUnit))
            }
        }
        .font(.caption2)
        .padding(6)
    }

    private func cornerText(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
    }

    private func cornerHeart(_ heartRate: HeartRateDisplayPresentation) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.caption2)
            Text(heartRate.valueText)
                .monospacedDigit()
        }
        .foregroundStyle(heartRate.color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.thinMaterial, in: Capsule())
    }

    private var heartRateDisplay: HeartRateDisplayPresentation {
        HeartRateDisplayPresentation(heartRate: snapshot.heartRate, settings: settings.heartRate)
    }

    private var region: MKCoordinateRegion {
        let last = snapshot.route.last ?? RoutePoint(latitude: 37.3327, longitude: -122.0053, altitudeMeters: nil, timestamp: Date(), horizontalAccuracy: nil)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
            span: MKCoordinateSpan(latitudeDelta: zoomSpan, longitudeDelta: zoomSpan)
        )
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        snapshot.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        snapshot.route.last.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

private extension HeartRateDisplayPresentation {
    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }
}

struct WatchControlsPage: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    let onPauseResume: () -> Void
    let onRequestEnd: () -> Void

    var body: some View {
        let controls = WorkoutControlPresentation(
            isPaused: workoutManager.isPaused,
            isFinishing: workoutManager.isFinishing
        )

        VStack(spacing: 10) {
            Button {
                onPauseResume()
            } label: {
                Label(controls.pauseTitle, systemImage: controls.pauseSystemImage)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pauseGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .disabled(!controls.isPauseEnabled)

            Button(role: .destructive) {
                onRequestEnd()
            } label: {
                Label(controls.endTitle, systemImage: controls.endSystemImage)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(endGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .disabled(!controls.isEndEnabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pauseGradient: LinearGradient {
        LinearGradient(
            colors: workoutManager.isPaused ? [.green, .cyan] : [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var endGradient: LinearGradient {
        LinearGradient(colors: [.pink, .red], startPoint: .leading, endPoint: .trailing)
    }
}

private struct WatchEndConfirmationView: View {
    let onCancel: () -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: proxy.size.height / 2)
                .background(Color.gray.opacity(0.28))

                Button(role: .destructive, action: onEnd) {
                    Label("End", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: proxy.size.height / 2)
                .background(Color.red.opacity(0.82))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }
}

private struct WatchEndTrimPromptView: View {
    let suggestion: WorkoutEndTrimSuggestion
    let onKeepAll: () -> Void
    let onTrim: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: suggestion.reason == .vehicleMovement ? "car.fill" : "figure.stand")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("Trim Workout End?")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(reasonText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(WorkoutFormatter.duration(suggestion.trimEndSeconds))
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            HStack(spacing: 7) {
                Button("Keep All", action: onKeepAll)
                    .buttonStyle(.bordered)
                Button("Auto Trim", action: onTrim)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }

    private var reasonText: String {
        switch suggestion.reason {
        case .stoppedMoving:
            return "Very little movement was found at the end."
        case .vehicleMovement:
            return "Slow movement followed by driving was found."
        }
    }
}
