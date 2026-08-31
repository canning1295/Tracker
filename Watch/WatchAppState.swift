import Foundation
import WatchConnectivity

final class WatchWorkoutCompletionOutbox {
    private let defaults: UserDefaults
    private let storageKey = "pendingWatchWorkoutCompletions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func enqueue(_ completion: WatchWorkoutCompletion) {
        var pending = load()
        guard !pending.contains(where: { $0.id == completion.id }) else { return }
        pending.append(completion)
        save(pending)
    }

    func flush(on session: WCSession) {
        guard session.activationState == .activated else {
            session.activate()
            return
        }

        let pending = load()
        guard !pending.isEmpty else { return }

        for completion in pending {
            let payload = completion.payload
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
            session.transferUserInfo(payload)
        }
        save([])
    }

    private func load() -> [WatchWorkoutCompletion] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([WatchWorkoutCompletion].self, from: data)) ?? []
    }

    private func save(_ completions: [WatchWorkoutCompletion]) {
        if completions.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(completions) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

final class WatchAppState: NSObject, ObservableObject, WCSessionDelegate {
    @Published var settings: WorkoutSettings
    @Published var intervals: [IntervalWorkout]
    @Published var requestedStartActivity: WorkoutActivity?
    @Published var pendingRemoteCommand: WatchWorkoutRemoteCommand?

    private let store = SettingsStore()
    private let completionOutbox = WatchWorkoutCompletionOutbox()
    private var settingsObserver: NSObjectProtocol?

    override init() {
        self.settings = store.loadSettings()
        self.intervals = store.loadIntervals()
        super.init()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: TrackerSettingsChange.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let settings = TrackerSettingsChange.settings(from: notification),
                  self.settings != settings else {
                return
            }
            self.settings = settings
            self.store.saveSettings(settings)
            self.sendSettingsToPhone()
        }
        activateConnectivity()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if WCSession.default.activationState == .activated {
            completionOutbox.flush(on: WCSession.default)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            self.completionOutbox.flush(on: session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async {
            self.completionOutbox.flush(on: session)
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil,
              let completion = WatchWorkoutCompletion(payload: userInfoTransfer.userInfo) else {
            return
        }
        DispatchQueue.main.async {
            self.completionOutbox.enqueue(completion)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let data = applicationContext["settings"] as? Data,
               let settings = try? JSONDecoder().decode(WorkoutSettings.self, from: data) {
                self.settings = settings
                self.store.saveSettings(settings)
            }
            if let data = applicationContext["intervals"] as? Data,
               let intervals = try? JSONDecoder().decode([IntervalWorkout].self, from: data) {
                self.intervals = intervals
                self.store.saveIntervals(intervals)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveStartPayload(message)
        receiveSettingsPayload(message)
        receiveRemoteCommandPayload(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveStartPayload(userInfo)
        receiveSettingsPayload(userInfo)
        receiveRemoteCommandPayload(userInfo)
    }

    func consumePendingIntentStart() -> WorkoutActivity? {
        PendingWorkoutStartStore.consume()
    }

    func clearRequestedStart() {
        requestedStartActivity = nil
    }

    func consumePendingIntentCommand() -> WatchWorkoutRemoteCommand? {
        PendingWorkoutCommandStore.consume()
    }

    func clearPendingRemoteCommand() {
        pendingRemoteCommand = nil
    }

    func enqueueRemoteCommand(_ command: WatchWorkoutRemoteCommand) {
        pendingRemoteCommand = command
    }

    func setTouchControlsEnabled(_ enabled: Bool) {
        guard settings.touchControlsEnabled != enabled else { return }
        settings.touchControlsEnabled = enabled
        store.saveSettings(settings)
        sendSettingsToPhone()
    }

    /// Live status is only useful while the phone is actually reachable, so it is
    /// sent as a message and deliberately not queued for later delivery.
    func sendLiveSession(_ status: WatchLiveSessionStatus?) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(WatchLiveSessionEnvelope(status: status)) else {
            return
        }
        WCSession.default.sendMessage(
            [WatchConnectivityPayloadKey.liveSession: data],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    private func receiveRemoteCommandPayload(_ payload: [String: Any]) {
        guard let raw = payload[WatchConnectivityPayloadKey.remoteCommand] as? String,
              let command = WatchWorkoutRemoteCommand(rawValue: raw) else {
            return
        }
        DispatchQueue.main.async {
            self.pendingRemoteCommand = command
        }
    }

    private func receiveStartPayload(_ payload: [String: Any]) {
        guard let data = payload[WatchConnectivityPayloadKey.startActivity] as? Data,
              let activity = try? JSONDecoder().decode(WorkoutActivity.self, from: data) else {
            return
        }
        DispatchQueue.main.async {
            self.requestedStartActivity = activity
        }
    }

    private func sendSettingsToPhone() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(settings) else {
            return
        }
        let payload: [String: Any] = [WatchConnectivityPayloadKey.settings: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }

    private func receiveSettingsPayload(_ payload: [String: Any]) {
        guard let data = payload[WatchConnectivityPayloadKey.settings] as? Data,
              let settings = try? JSONDecoder().decode(WorkoutSettings.self, from: data) else {
            return
        }
        DispatchQueue.main.async {
            guard self.settings != settings else { return }
            self.settings = settings
            self.store.saveSettings(settings)
        }
    }
}
