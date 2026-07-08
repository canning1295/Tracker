import Foundation
import WatchConnectivity

enum WatchConnectivityReadinessStatus {
    case ready
    case warning
    case blocked
}

struct WatchConnectivityReadiness {
    var status: WatchConnectivityReadinessStatus
    var message: String
}

final class PhoneConnectivityClient: NSObject, WCSessionDelegate {
    var onWorkoutFinished: ((Date?) -> Void)?
    var onSettingsReceived: ((WorkoutSettings) -> Void)?
    private var pendingApplicationContext: [String: Any]?
    private var pendingUserInfoTransfers: [[String: Any]] = []

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        if session.activationState == .activated {
            flushPendingTransfers(on: session)
        }
    }

    func readiness() -> WatchConnectivityReadiness {
        guard WCSession.isSupported(), let session else {
            return WatchConnectivityReadiness(status: .blocked, message: "WatchConnectivity is not supported on this device.")
        }

        guard session.activationState == .activated else {
            return WatchConnectivityReadiness(status: .warning, message: "Watch connection is still activating.")
        }

        guard session.isPaired else {
            return WatchConnectivityReadiness(status: .blocked, message: "No Apple Watch is paired with this iPhone.")
        }

        guard session.isWatchAppInstalled else {
            return WatchConnectivityReadiness(status: .blocked, message: "The Tracker Watch app is not installed.")
        }

        if session.isReachable {
            return WatchConnectivityReadiness(status: .ready, message: "Watch app is reachable for immediate starts.")
        }

        return WatchConnectivityReadiness(status: .warning, message: "Watch app is installed but not reachable; starts will queue until the Watch is available.")
    }

    func send(settings: WorkoutSettings, intervals: [IntervalWorkout]) {
        guard let session else { return }
        guard let settingsData = try? JSONEncoder().encode(settings),
              let intervalsData = try? JSONEncoder().encode(intervals) else { return }

        let context: [String: Any] = [
            "settings": settingsData,
            "intervals": intervalsData
        ]

        guard session.activationState == .activated else {
            pendingApplicationContext = context
            session.activate()
            return
        }

        try? session.updateApplicationContext(context)
    }

    func sendStart(activity: WorkoutActivity) {
        guard let session else { return }
        guard let data = try? JSONEncoder().encode(activity) else { return }
        let payload: [String: Any] = [WatchConnectivityPayloadKey.startActivity: data]
        guard session.activationState == .activated else {
            pendingUserInfoTransfers.append(payload)
            session.activate()
            return
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        flushPendingTransfers(on: session)
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveWorkoutFinishedPayload(message)
        receiveSettingsPayload(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveWorkoutFinishedPayload(userInfo)
        receiveSettingsPayload(userInfo)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private func receiveWorkoutFinishedPayload(_ payload: [String: Any]) {
        guard payload[WatchConnectivityPayloadKey.workoutFinished] as? Bool == true else { return }
        let endedAt = payload[WatchConnectivityPayloadKey.endedAt] as? Date
        DispatchQueue.main.async {
            self.onWorkoutFinished?(endedAt)
        }
    }

    private func receiveSettingsPayload(_ payload: [String: Any]) {
        guard let data = payload[WatchConnectivityPayloadKey.settings] as? Data,
              let settings = try? JSONDecoder().decode(WorkoutSettings.self, from: data) else {
            return
        }
        DispatchQueue.main.async {
            self.onSettingsReceived?(settings)
        }
    }

    private func flushPendingTransfers(on session: WCSession) {
        if let context = pendingApplicationContext {
            try? session.updateApplicationContext(context)
            pendingApplicationContext = nil
        }

        pendingUserInfoTransfers.forEach { session.transferUserInfo($0) }
        pendingUserInfoTransfers = []
    }
}
