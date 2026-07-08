import MapKit
import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var watchState: WatchAppState
    @State private var page = 0

    var body: some View {
        ZStack {
            TabView(selection: $page) {
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

                WatchControlsPage()
                    .tag(controlsTag)
            }
            .allowsHitTesting(watchState.settings.touchControlsEnabled)

            if !watchState.settings.touchControlsEnabled {
                TouchControlsLockedOverlay()
                    .allowsHitTesting(false)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .navigationBarBackButtonHidden(true)
    }

    private var hasOutdoorMap: Bool {
        workoutManager.activity?.environment == .outdoor
    }

    private var controlsTag: Int {
        hasOutdoorMap ? 2 : 1
    }
}

private struct TouchControlsLockedOverlay: View {
    var body: some View {
        VStack {
            Label("Touch Off", systemImage: "hand.raised.slash.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
            Spacer()
        }
        .padding(.top, 4)
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

        VStack(spacing: 6) {
            if let statusText = controls.statusText {
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isFinishing ? Color.secondary : Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(WorkoutFormatter.duration(snapshot.elapsedSeconds))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if let interval {
                WatchIntervalProgressPanel(progress: IntervalTimeline.progress(for: interval, elapsedSeconds: snapshot.elapsedSeconds))
            }

            if showsDistanceAndPace {
                HStack {
                    MetricBlock(title: "HR", value: heartRateDisplay.valueText, color: heartRateDisplay.color)
                    MetricBlock(title: "Dist", value: WorkoutFormatter.distance(snapshot.distanceMeters, unit: settings.distanceUnit), color: .primary)
                }

                HStack {
                    MetricBlock(title: "Pace", value: WorkoutFormatter.pace(snapshot.paceSecondsPerUnit, unit: settings.distanceUnit), color: .primary)
                    MetricBlock(title: "Act Cal", value: activeCaloriesText, color: .primary)
                }
            } else {
                HStack {
                    MetricBlock(title: "HR", value: heartRateDisplay.valueText, color: heartRateDisplay.color)
                    MetricBlock(title: "Act Cal", value: activeCaloriesText, color: .primary)
                }
            }
        }
        .padding(.horizontal, 8)
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
        .frame(maxWidth: .infinity)
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
                    .stroke(.orange, lineWidth: 4)
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
    @EnvironmentObject private var watchState: WatchAppState

    var body: some View {
        let controls = WorkoutControlPresentation(
            isPaused: workoutManager.isPaused,
            isFinishing: workoutManager.isFinishing
        )

        VStack(spacing: 8) {
            Button {
                workoutManager.togglePause()
            } label: {
                Label(controls.pauseTitle, systemImage: controls.pauseSystemImage)
            }
            .disabled(!controls.isPauseEnabled)

            Button(role: .destructive) {
                workoutManager.end()
            } label: {
                Label(controls.endTitle, systemImage: controls.endSystemImage)
            }
            .disabled(!controls.isEndEnabled)

            Button {
                watchState.setTouchControlsEnabled(!watchState.settings.touchControlsEnabled)
            } label: {
                Label(touchTitle, systemImage: touchSystemImage)
            }
        }
        .buttonStyle(.bordered)
    }

    private var touchTitle: String {
        watchState.settings.touchControlsEnabled ? "Touch Off" : "Touch On"
    }

    private var touchSystemImage: String {
        watchState.settings.touchControlsEnabled ? "hand.raised.slash" : "hand.tap"
    }
}
