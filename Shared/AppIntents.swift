import AppIntents
import Foundation

struct OpenTrackerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tracker"
    static var description = IntentDescription("Open Tracker on Apple Watch or iPhone.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

enum IntentWorkoutActivity: String, AppEnum {
    case outdoorRun
    case outdoorWalk
    case outdoorBike
    case indoorRun
    case indoorWalk
    case indoorElliptical
    case indoorBike
    case weights

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout")
    static var caseDisplayRepresentations: [IntentWorkoutActivity: DisplayRepresentation] = [
        .outdoorRun: "Outdoor Run",
        .outdoorWalk: "Outdoor Walk",
        .outdoorBike: "Outdoor Bike",
        .indoorRun: "Indoor Run",
        .indoorWalk: "Indoor Walk",
        .indoorElliptical: "Elliptical",
        .indoorBike: "Indoor Bike",
        .weights: "Weights"
    ]

    var activity: WorkoutActivity {
        WorkoutActivity(rawValue: rawValue) ?? .outdoorRun
    }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription("Open Tracker ready to start the selected activity.")
    static var openAppWhenRun = true

    @Parameter(title: "Activity")
    var activity: IntentWorkoutActivity

    init() {
        self.activity = .outdoorRun
    }

    init(activity: IntentWorkoutActivity) {
        self.activity = activity
    }

    func perform() async throws -> some IntentResult {
        PendingWorkoutStartStore.set(activity.activity)
        return .result()
    }
}

struct TouchOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Touch On"
    static var description = IntentDescription("Enable touch controls in Tracker.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TrackerSettingsWriter.setTouchControlsEnabled(true)
        return .result(dialog: "Touch controls are on in Tracker.")
    }
}

struct TouchOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Touch Off"
    static var description = IntentDescription("Disable touch controls in Tracker.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TrackerSettingsWriter.setTouchControlsEnabled(false)
        return .result(dialog: "Touch controls are off in Tracker.")
    }
}

struct TrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TouchOnIntent(),
            phrases: [
                "Touch on in \(.applicationName)",
                "Turn touch on in \(.applicationName)",
                "Enable touch in \(.applicationName)"
            ],
            shortTitle: "Touch On",
            systemImageName: "hand.tap"
        )

        AppShortcut(
            intent: TouchOffIntent(),
            phrases: [
                "Touch off in \(.applicationName)",
                "Turn touch off in \(.applicationName)",
                "Disable touch in \(.applicationName)"
            ],
            shortTitle: "Touch Off",
            systemImageName: "hand.raised.slash"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .outdoorRun),
            phrases: [
                "Start my run in \(.applicationName)",
                "Start an outdoor run in \(.applicationName)"
            ],
            shortTitle: "Outdoor Run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .outdoorWalk),
            phrases: [
                "Start my walk in \(.applicationName)",
                "Start an outdoor walk in \(.applicationName)"
            ],
            shortTitle: "Outdoor Walk",
            systemImageName: "figure.walk"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .outdoorBike),
            phrases: [
                "Start outdoor bike in \(.applicationName)",
                "Start cycling outside in \(.applicationName)"
            ],
            shortTitle: "Outdoor Bike",
            systemImageName: "bicycle"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .indoorRun),
            phrases: [
                "Start indoor run in \(.applicationName)",
                "Start treadmill run in \(.applicationName)"
            ],
            shortTitle: "Indoor Run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .indoorWalk),
            phrases: [
                "Start indoor walk in \(.applicationName)",
                "Start treadmill walk in \(.applicationName)"
            ],
            shortTitle: "Indoor Walk",
            systemImageName: "figure.walk"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .indoorElliptical),
            phrases: [
                "Start elliptical in \(.applicationName)",
                "Start indoor elliptical in \(.applicationName)"
            ],
            shortTitle: "Elliptical",
            systemImageName: "figure.elliptical"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .indoorBike),
            phrases: [
                "Start indoor bike in \(.applicationName)",
                "Start cycling indoors in \(.applicationName)"
            ],
            shortTitle: "Indoor Bike",
            systemImageName: "bicycle"
        )

        AppShortcut(
            intent: StartWorkoutIntent(activity: .weights),
            phrases: [
                "Start weights in \(.applicationName)",
                "Start strength training in \(.applicationName)"
            ],
            shortTitle: "Weights",
            systemImageName: "dumbbell"
        )
    }
}
