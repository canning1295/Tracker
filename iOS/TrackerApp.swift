import SwiftUI

@main
struct TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appState)
                .task {
                    appState.consumePendingIntentStart()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    appState.consumePendingIntentStart()
                }
                .onOpenURL { url in
                    Task {
                        await appState.handleOpenURL(url)
                    }
                }
        }
    }
}
