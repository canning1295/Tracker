import SwiftUI

@main
struct TrackerApp: App {
    var body: some Scene {
        WindowGroup {
            AppStartupView()
        }
    }
}

@MainActor
private struct AppStartupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState?
    @State private var didStartBootstrapping = false
    @State private var pendingOpenURL: URL?

    var body: some View {
        content
            .task {
                await bootstrapIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                appState?.consumePendingIntentStart()
            }
            .onOpenURL { url in
                guard let appState else {
                    pendingOpenURL = url
                    return
                }

                Task {
                    await appState.handleOpenURL(url)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let appState {
            AppRootView()
                .environment(appState)
        } else {
            HumorousLoadingView(
                title: "Starting Tracker",
                phrases: LoadingPhraseProvider.startupPhrases
            )
        }
    }

    private func bootstrapIfNeeded() async {
        guard appState == nil, !didStartBootstrapping else { return }
        didStartBootstrapping = true

        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let state = AppState()
        appState = state
        state.consumePendingIntentStart()

        if let pendingOpenURL {
            self.pendingOpenURL = nil
            await state.handleOpenURL(pendingOpenURL)
        }
    }
}
