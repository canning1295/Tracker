import SwiftUI

@main
struct TrackerWatchApp: App {
    @StateObject private var workoutManager = WorkoutSessionManager()
    @StateObject private var watchState = WatchAppState()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(workoutManager)
                .environmentObject(watchState)
        }
    }
}

