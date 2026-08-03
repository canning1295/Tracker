import Foundation

struct SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "workout.settings.v1"
    private let intervalsKey = "workout.intervals.v1"
    private let activityEditsKey = "workout.activityEdits.v1"
    private let stravaUploadsKey = "workout.stravaUploads.v1"
    private let deletedWorkoutIDsKey = "workout.deletedWorkoutIDs.v1"
    private let excludedBestEffortWorkoutIDsKey = "workout.excludedBestEffortWorkoutIDs.v1"
    private let bestEffortCacheKey = "workout.bestEffortCache.v3"

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

    func loadDeletedWorkoutIDs() -> Set<UUID> {
        guard let data = defaults.data(forKey: deletedWorkoutIDsKey) else { return [] }
        let ids = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        return Set(ids)
    }

    func saveDeletedWorkoutIDs(_ ids: Set<UUID>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        defaults.set(data, forKey: deletedWorkoutIDsKey)
    }

    func loadExcludedBestEffortWorkoutIDs() -> Set<UUID> {
        guard let data = defaults.data(forKey: excludedBestEffortWorkoutIDsKey) else { return [] }
        let ids = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        return Set(ids)
    }

    func saveExcludedBestEffortWorkoutIDs(_ ids: Set<UUID>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        defaults.set(data, forKey: excludedBestEffortWorkoutIDsKey)
    }

    func loadBestEffortCache() -> BestEffortCache {
        guard let data = defaults.data(forKey: bestEffortCacheKey) else { return BestEffortCache() }
        return (try? JSONDecoder().decode(BestEffortCache.self, from: data)) ?? BestEffortCache()
    }

    func saveBestEffortCache(_ cache: BestEffortCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: bestEffortCacheKey)
    }
}
