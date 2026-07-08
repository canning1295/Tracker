import Foundation

enum TrackerSettingsChange {
    static let notificationName = Notification.Name("TrackerSettingsDidChange")
    private static let settingsKey = "settings"

    static func post(_ settings: WorkoutSettings) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [settingsKey: settings]
        )
    }

    static func settings(from notification: Notification) -> WorkoutSettings? {
        notification.userInfo?[settingsKey] as? WorkoutSettings
    }
}

enum TrackerSettingsWriter {
    @discardableResult
    static func setTouchControlsEnabled(
        _ enabled: Bool,
        store: SettingsStore = SettingsStore()
    ) -> WorkoutSettings {
        var settings = store.loadSettings()
        settings.touchControlsEnabled = enabled
        store.saveSettings(settings)
        TrackerSettingsChange.post(settings)
        return settings
    }
}
