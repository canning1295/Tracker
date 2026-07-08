import Foundation

struct SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "workout.settings.v1"
    private let intervalsKey = "workout.intervals.v1"
    private let activityEditsKey = "workout.activityEdits.v1"
    private let stravaUploadsKey = "workout.stravaUploads.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> WorkoutSettings {
        guard let data = defaults.data(forKey: settingsKey) else { return .defaults }
        return (try? JSONDecoder().decode(WorkoutSettings.self, from: data)) ?? .defaults
    }

    func saveSettings(_ settings: WorkoutSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    func loadIntervals() -> [IntervalWorkout] {
        guard let data = defaults.data(forKey: intervalsKey) else { return [] }
        return (try? JSONDecoder().decode([IntervalWorkout].self, from: data)) ?? []
    }

    func saveIntervals(_ intervals: [IntervalWorkout]) {
        guard let data = try? JSONEncoder().encode(intervals) else { return }
        defaults.set(data, forKey: intervalsKey)
    }

    func loadActivityEdits() -> [ActivityEdit] {
        guard let data = defaults.data(forKey: activityEditsKey) else { return [] }
        return (try? JSONDecoder().decode([ActivityEdit].self, from: data)) ?? []
    }

    func saveActivityEdits(_ edits: [ActivityEdit]) {
        guard let data = try? JSONEncoder().encode(edits) else { return }
        defaults.set(data, forKey: activityEditsKey)
    }

    func loadStravaUploads() -> [StravaUploadRecord] {
        guard let data = defaults.data(forKey: stravaUploadsKey) else { return [] }
        return (try? JSONDecoder().decode([StravaUploadRecord].self, from: data)) ?? []
    }

    func saveStravaUploads(_ uploads: [StravaUploadRecord]) {
        guard let data = try? JSONEncoder().encode(uploads) else { return }
        defaults.set(data, forKey: stravaUploadsKey)
    }
}
