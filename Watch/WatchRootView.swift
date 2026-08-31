import SwiftUI

private enum WatchRoute: Hashable {
    case activitySelection(ActivityEnvironment)
    case startWorkout(WorkoutActivity)
    case intervalList
}

private enum WatchHomeChoice: String, CaseIterable, Identifiable {
    case outdoor
    case indoor
    case workouts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outdoor: return "Outdoor"
        case .indoor: return "Indoor"
        case .workouts: return "Workouts"
        }
    }

    var systemImage: String {
        switch self {
        case .outdoor: return "location"
        case .indoor: return "house"
        case .workouts: return "timer"
        }
    }

    var buttonGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .outdoor:
            colors = [
                Color(red: 0.25, green: 0.65, blue: 0.28),
                Color(red: 0.17, green: 0.55, blue: 0.89)
            ]
        case .indoor:
            colors = [
                Color(red: 0.25, green: 0.32, blue: 0.71),
                Color(red: 0.61, green: 0.16, blue: 0.69)
            ]
        case .workouts:
            colors = [
                Color(red: 0.93, green: 0.18, blue: 0.18),
                Color(red: 1.00, green: 0.55, blue: 0.00)
            ]
        }

        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var watchState: WatchAppState
    @State private var path: [WatchRoute] = []
    @State private var outdoorSelectionIndex = 0
    @State private var indoorSelectionIndex = 0
    @State private var intervalSelectionIndex = 0

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                WatchHomeView(onSelect: openHomeChoice)
                .navigationDestination(for: WatchRoute.self) { route in
                    switch route {
                    case .activitySelection(let environment):
                        ActivitySelectionView(
                            environment: environment,
                            selectionIndex: selectionBinding(for: environment),
                            onSelect: { activity in
                                path.append(.startWorkout(activity))
                            },
                            onBack: {
                                _ = path.popLast()
                            }
                        )
                    case .startWorkout(let activity):
                        StartWorkoutView(
                            activity: activity,
                            onBack: {
                                _ = path.popLast()
                            }
                        )
                    case .intervalList:
                        WatchIntervalListView(
                            selectionIndex: $intervalSelectionIndex,
                            onBack: {
                                _ = path.popLast()
                            }
                        )
                    }
                }
                .navigationDestination(isPresented: Binding(
                    get: { workoutManager.isActive },
                    set: { _ in }
                )) {
                    ActiveWorkoutView()
                }
            }

            if let summary = workoutManager.completedWorkoutSummary {
                WatchWorkoutSummaryView(
                    summary: summary,
                    settings: watchState.settings,
                    onDismiss: dismissWorkoutSummary
                )
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottom) {
            if let status = workoutManager.startStatus,
               !workoutManager.isActive,
               workoutManager.completedWorkoutSummary == nil {
                WatchStatusBanner(status: status)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
            }
        }
        ._statusBarHidden(true)
        .onAppear {
            workoutManager.updateSettings(watchState.settings)
            workoutManager.beginLocationAcquisition()
            consumePendingIntentStart()
        }
        .onChange(of: watchState.settings) { _, settings in
            workoutManager.updateSettings(settings)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                workoutManager.beginLocationAcquisition()
                consumePendingIntentStart()
            } else {
                workoutManager.stopPreworkoutLocationAcquisition()
            }
        }
        .onChange(of: watchState.requestedStartActivity) { _, activity in
            guard let activity, workoutManager.completedWorkoutSummary == nil else { return }
            start(activity)
            watchState.clearRequestedStart()
        }
    }

    private func consumePendingIntentStart() {
        guard !workoutManager.isActive,
              workoutManager.completedWorkoutSummary == nil,
              let pending = watchState.consumePendingIntentStart() else {
            return
        }
        start(pending)
    }

    private func dismissWorkoutSummary() {
        workoutManager.dismissCompletedWorkoutSummary()
        path.removeAll()

        if let requested = watchState.requestedStartActivity {
            start(requested)
            watchState.clearRequestedStart()
        } else {
            consumePendingIntentStart()
        }
    }

    private func start(_ activity: WorkoutActivity) {
        workoutManager.updateSettings(watchState.settings)
        workoutManager.start(activity: activity)
    }

    private func openHomeChoice(_ choice: WatchHomeChoice) {
        switch choice {
        case .outdoor:
            path.append(.activitySelection(.outdoor))
        case .indoor:
            path.append(.activitySelection(.indoor))
        case .workouts:
            path.append(.intervalList)
        }
    }

    private func selectionBinding(for environment: ActivityEnvironment) -> Binding<Int> {
        Binding {
            switch environment {
            case .outdoor: return outdoorSelectionIndex
            case .indoor: return indoorSelectionIndex
            }
        } set: { newValue in
            setActivitySelectionIndex(environment, to: newValue)
        }
    }

    private func setActivitySelectionIndex(_ environment: ActivityEnvironment, to index: Int) {
        let clamped = min(max(index, 0), max(activityCount(for: environment) - 1, 0))
        switch environment {
        case .outdoor:
            outdoorSelectionIndex = clamped
        case .indoor:
            indoorSelectionIndex = clamped
        }
    }

    private func activityCount(for environment: ActivityEnvironment) -> Int {
        switch environment {
        case .outdoor: return watchState.settings.outdoorOrder.count
        case .indoor: return watchState.settings.indoorOrder.count
        }
    }
}

private struct WatchHomeView: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    let onSelect: (WatchHomeChoice) -> Void

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 8
            let verticalMargin: CGFloat = 26
            let buttonHeight = max(54, min(60, (geometry.size.height - (spacing * 2) - (verticalMargin * 2)) / 3))

            VStack(spacing: spacing) {
                ForEach(WatchHomeChoice.allCases) { choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        Label(choice.title, systemImage: choice.systemImage)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                    .background(choice.buttonGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .offset(y: -3)
        }
        .toolbar(.hidden, for: .navigationBar)
        ._statusBarHidden(true)
        .ignoresSafeArea(.container)
        .onAppear {
            workoutManager.beginLocationAcquisition()
        }
    }
}

struct ActivitySelectionView: View {
    @EnvironmentObject private var watchState: WatchAppState
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    let environment: ActivityEnvironment
    @Binding var selectionIndex: Int
    let onSelect: (WorkoutActivity) -> Void
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                WatchScreenHeader(title: environment.displayName, onBack: onBack)

                if activities.isEmpty {
                    Spacer(minLength: 0)
                    Text("No workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else if environment == .outdoor {
                    outdoorButtons
                } else {
                    indoorButtons
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .toolbar(.hidden, for: .navigationBar)
        ._statusBarHidden(true)
        .ignoresSafeArea(.container)
        .onAppear {
            if environment == .outdoor {
                workoutManager.beginLocationAcquisition()
            } else {
                workoutManager.stopPreworkoutLocationAcquisition()
            }
        }
    }

    private var activities: [WorkoutActivity] {
        environment == .outdoor ? watchState.settings.outdoorOrder : watchState.settings.indoorOrder
    }

    private var outdoorButtons: some View {
        VStack(spacing: 8) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                activityButton(activity, at: index)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var indoorButtons: some View {
        let rowCount = (activities.count + 1) / 2

        return VStack(spacing: 8) {
            ForEach(0..<rowCount, id: \.self) { row in
                let firstIndex = row * 2
                let secondIndex = firstIndex + 1

                HStack(spacing: 8) {
                    activityButton(activities[firstIndex], at: firstIndex)

                    if activities.indices.contains(secondIndex) {
                        activityButton(activities[secondIndex], at: secondIndex)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func activityButton(_ activity: WorkoutActivity, at index: Int) -> some View {
        Button {
            selectionIndex = index
            onSelect(activity)
        } label: {
            Label(activity.displayName, systemImage: activity.symbolName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(activity.selectionGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct WatchScreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: 40, height: 34)
                .accessibilityHidden(true)
        }
        .frame(height: 34)
    }
}

private extension WorkoutActivity {
    var selectionGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .outdoorRun:
            colors = [.red, .orange]
        case .outdoorWalk:
            colors = [
                Color(red: 0.88, green: 0.49, blue: 0.03),
                Color(red: 0.25, green: 0.65, blue: 0.28)
            ]
        case .outdoorBike:
            colors = [
                Color(red: 0.03, green: 0.65, blue: 0.72),
                Color(red: 0.12, green: 0.42, blue: 0.82)
            ]
        case .indoorRun:
            colors = [
                Color(red: 0.17, green: 0.55, blue: 0.89),
                Color(red: 0.25, green: 0.32, blue: 0.71)
            ]
        case .indoorWalk:
            colors = [
                Color(red: 0.25, green: 0.32, blue: 0.71),
                Color(red: 0.61, green: 0.16, blue: 0.69)
            ]
        case .indoorElliptical:
            colors = [
                Color(red: 0.61, green: 0.16, blue: 0.69),
                Color(red: 0.93, green: 0.18, blue: 0.38)
            ]
        case .indoorBike:
            colors = [
                Color(red: 0.93, green: 0.18, blue: 0.18),
                Color(red: 1.00, green: 0.55, blue: 0.00)
            ]
        case .weights:
            colors = [
                Color(red: 0.88, green: 0.49, blue: 0.03),
                Color(red: 0.25, green: 0.65, blue: 0.28)
            ]
        }

        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct StartWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    let activity: WorkoutActivity
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                WatchScreenHeader(title: activity.displayName, onBack: onBack)

                if activity.environment == .outdoor {
                    GPSReadinessCard(readiness: workoutManager.gpsReadiness)
                        .frame(height: 58)
                } else if IndoorDistanceEstimator.anchorPaceMinutesPerMile(for: activity) != nil {
                    IndoorDistanceEstimateCard(activity: activity)
                        .frame(height: 58)
                }

                Button {
                    workoutManager.start(activity: activity)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: actionSymbol)
                            .font(.title2.weight(.bold))

                        Text(actionTitle)
                            .font(.title2.weight(.bold))

                        Text("\(activity.environment.displayName) \(activity.displayName)")
                            .font(.caption.weight(.semibold))
                            .opacity(0.82)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(activity.selectionGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .disabled(workoutManager.isStarting)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .toolbar(.hidden, for: .navigationBar)
        ._statusBarHidden(true)
        .ignoresSafeArea(.container)
        .onAppear {
            if activity.environment == .outdoor {
                workoutManager.beginLocationAcquisition()
            } else {
                workoutManager.stopPreworkoutLocationAcquisition()
            }
        }
    }

    private var actionTitle: String {
        if workoutManager.isStarting { return "Starting" }
        if workoutManager.startStatus?.isFailure == true { return "Retry" }
        return "Start"
    }

    private var actionSymbol: String {
        if workoutManager.isStarting { return "hourglass" }
        if workoutManager.startStatus?.isFailure == true { return "arrow.clockwise.circle" }
        return "play.fill"
    }

}

private struct IndoorDistanceEstimateCard: View {
    let activity: WorkoutActivity

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "heart.text.square.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(width: 30, height: 30)
                .background(.pink.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated Distance")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(calibrationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.pink.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var calibrationText: String {
        guard let minutes = IndoorDistanceEstimator.anchorPaceMinutesPerMile(for: activity) else {
            return "Uses your heart-rate zones"
        }
        return "110 bpm ≈ 1 mi in \(Int(minutes.rounded())) min"
    }
}

private struct GPSReadinessCard: View {
    let readiness: GPSReadiness

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if showsProgress {
                    ProgressView()
                        .tint(statusColor)
                } else {
                    Image(systemName: symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
            }
            .frame(width: 30, height: 30)
            .background(statusColor.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch readiness {
        case .checking: return "Checking GPS"
        case .requestingPermission: return "Location Access"
        case .unavailable: return "GPS Unavailable"
        case .acquiring(let accuracy): return accuracy == nil ? "Acquiring GPS" : "Improving GPS"
        case .ready: return "GPS Ready"
        }
    }

    private var detail: String {
        switch readiness {
        case .checking:
            return "Checking location services"
        case .requestingPermission:
            return "Permission is required"
        case .unavailable(let message):
            return message
        case .acquiring(let accuracy):
            return accuracyText(accuracy) ?? "Waiting for a location fix"
        case .ready(let accuracy):
            return accuracyText(accuracy) ?? "Accurate location acquired"
        }
    }

    private var symbolName: String {
        switch readiness {
        case .checking, .requestingPermission: return "location.circle"
        case .unavailable: return "location.slash.fill"
        case .acquiring: return "location.fill"
        case .ready: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch readiness {
        case .checking, .requestingPermission: return .blue
        case .unavailable: return .red
        case .acquiring: return .yellow
        case .ready: return .green
        }
    }

    private var showsProgress: Bool {
        switch readiness {
        case .checking, .requestingPermission, .acquiring(accuracyMeters: nil): return true
        default: return false
        }
    }

    private func accuracyText(_ accuracy: Double?) -> String? {
        guard let accuracy else { return nil }
        return "Accuracy ±\(Int(accuracy.rounded())) m"
    }
}

struct WatchIntervalListView: View {
    @EnvironmentObject private var watchState: WatchAppState
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @Binding var selectionIndex: Int
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 7) {
                WatchScreenHeader(title: "Workouts", onBack: onBack)

                if watchState.intervals.isEmpty {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No workouts")
                            .font(.headline)
                        Text("Create intervals on iPhone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: watchState.intervals.count > 3) {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(watchState.intervals.enumerated()), id: \.element.id) { index, interval in
                                Button {
                                    selectionIndex = index
                                    workoutManager.startInterval(interval)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "timer")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(interval.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(WorkoutFormatter.duration(TimeInterval(interval.totalSeconds)))
                                                .font(.caption2.monospacedDigit())
                                                .opacity(0.82)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .background(intervalGradient(at: index), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .toolbar(.hidden, for: .navigationBar)
        ._statusBarHidden(true)
        .ignoresSafeArea(.container)
        .onAppear {
            workoutManager.stopPreworkoutLocationAcquisition()
        }
    }

    private func intervalGradient(at index: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [.blue, .purple],
            [.purple, .pink],
            [.pink, .red],
            [.cyan, .blue],
            [.green, .cyan]
        ]
        return LinearGradient(
            colors: palettes[index % palettes.count],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct WatchStatusBanner: View {
    let status: WorkoutStartStatus

    var body: some View {
        Label(status.message, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(foreground)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbolName: String {
        switch status {
        case .starting: return "hourglass"
        case .warning: return "location.slash"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        switch status {
        case .starting: return .secondary
        case .warning: return .orange
        case .failure: return .red
        }
    }
}
