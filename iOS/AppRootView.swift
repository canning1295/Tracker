import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case activities
    case summary
    case workouts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activities: return "Activities"
        case .summary: return "Summary"
        case .workouts: return "Workouts"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .activities: return "list.bullet.rectangle"
        case .summary: return "chart.bar.xaxis"
        case .workouts: return "timer"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
struct AppRootView: View {
    @State private var selectedTab: AppTab = .activities
    @State private var activityPath: [WorkoutSummary] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $activityPath) {
                ActivityListView(activityPath: $activityPath)
            }
            .tabItem { Label(AppTab.activities.title, systemImage: AppTab.activities.symbolName) }
            .tag(AppTab.activities)

            NavigationStack {
                SummaryView()
            }
            .tabItem { Label(AppTab.summary.title, systemImage: AppTab.summary.symbolName) }
            .tag(AppTab.summary)

            NavigationStack {
                IntervalWorkoutListView()
            }
            .tabItem { Label(AppTab.workouts.title, systemImage: AppTab.workouts.symbolName) }
            .tag(AppTab.workouts)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName) }
            .tag(AppTab.settings)
        }
    }
}
