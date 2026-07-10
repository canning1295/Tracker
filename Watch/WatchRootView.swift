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
}

struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var watchState: WatchAppState
    @State private var path: [WatchRoute] = []
    @State private var homeSelectionIndex = 0
    @State private var outdoorSelectionIndex = 0
    @State private var indoorSelectionIndex = 0
    @State private var intervalSelectionIndex = 0

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                CrownMenu(
                    title: "Workout",
                    options: WatchHomeChoice.allCases,
                    selectionIndex: $homeSelectionIndex,
                    screenIndex: 0,
                    screenCount: 3,
                    onSelect: openHomeChoice,
                    fillRows: true
                ) { choice, isSelected in
                    CrownMenuRow(title: choice.title, systemImage: choice.systemImage, isSelected: isSelected, fillHeight: true)
                }
                .navigationBarTitleDisplayMode(.inline)
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
                                homeSelectionIndex = WatchHomeChoice.allCases.count - 1
                                _ = path.popLast()
                            }
                        )
                    case .startWorkout(let activity):
                        StartWorkoutView(
                            activity: activity,
                            onBack: {
                                setActivitySelectionIndex(activity.environment, to: activityCount(for: activity.environment) - 1)
                                _ = path.popLast()
                            }
                        )
                    case .intervalList:
                        WatchIntervalListView(
                            selectionIndex: $intervalSelectionIndex,
                            onBack: {
                                homeSelectionIndex = WatchHomeChoice.allCases.count - 1
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
        .onAppear {
            workoutManager.updateSettings(watchState.settings)
            consumePendingIntentStart()
        }
        .onChange(of: watchState.settings) { _, settings in
            workoutManager.updateSettings(settings)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            consumePendingIntentStart()
        }
        .onChange(of: watchState.requestedStartActivity) { _, activity in
            guard let activity, workoutManager.completedWorkoutSummary == nil else { return }
            start(activity)
            watchState.clearRequestedStart()
        }
        .onChange(of: workoutManager.isActive) { _, isActive in
            guard isActive, watchState.settings.autoDisableTouchOnWorkoutStart else { return }
            watchState.setTouchControlsEnabled(false)
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

struct ActivitySelectionView: View {
    @EnvironmentObject private var watchState: WatchAppState
    let environment: ActivityEnvironment
    @Binding var selectionIndex: Int
    let onSelect: (WorkoutActivity) -> Void
    let onBack: () -> Void

    var body: some View {
        CrownMenu(
            title: environment.displayName,
            options: activities,
            selectionIndex: $selectionIndex,
            screenIndex: 1,
            screenCount: 3,
            onSelect: onSelect,
            onBack: onBack,
            topPadding: 0
        ) { activity, isSelected in
            CrownMenuRow(title: activity.displayName, systemImage: activity.symbolName, isSelected: isSelected)
        }
        ._statusBarHidden(true)
    }

    private var activities: [WorkoutActivity] {
        environment == .outdoor ? watchState.settings.outdoorOrder : watchState.settings.indoorOrder
    }
}

private enum StartWorkoutAction: String, CaseIterable, Identifiable {
    case start

    var id: String { rawValue }
}

struct StartWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    let activity: WorkoutActivity
    let onBack: () -> Void
    @State private var selectionIndex = 0

    var body: some View {
        CrownMenu(
            title: activity.displayName,
            options: StartWorkoutAction.allCases,
            selectionIndex: $selectionIndex,
            screenIndex: 2,
            screenCount: 3,
            onSelect: { _ in
                workoutManager.start(activity: activity)
            },
            onBack: onBack
        ) { _, isSelected in
            CrownMenuRow(title: actionTitle, systemImage: actionSymbol, isSelected: isSelected, subtitle: actionSubtitle)
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

    private var actionSubtitle: String {
        workoutManager.startStatus?.message ?? activity.environment.displayName
    }
}

struct WatchIntervalListView: View {
    @EnvironmentObject private var watchState: WatchAppState
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @Binding var selectionIndex: Int
    let onBack: () -> Void

    var body: some View {
        CrownMenu(
            title: "Workouts",
            options: watchState.intervals,
            selectionIndex: $selectionIndex,
            screenIndex: 1,
            screenCount: 2,
            onSelect: { interval in
                workoutManager.startInterval(interval)
            },
            onBack: onBack
        ) { interval, isSelected in
            CrownMenuRow(
                title: interval.name,
                systemImage: "timer",
                isSelected: isSelected,
                subtitle: WorkoutFormatter.duration(TimeInterval(interval.totalSeconds))
            )
        }
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
