import CoreLocation
import Foundation
import HealthKit
import WatchKit
import WatchConnectivity

enum WorkoutStartStatus: Equatable {
    case starting(String)
    case warning(String)
    case failure(String)

    var message: String {
        switch self {
        case .starting(let message), .warning(let message), .failure(let message):
            return message
        }
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

final class WorkoutSessionManager: NSObject, ObservableObject {
    @Published private(set) var snapshot = WorkoutMetricSnapshot.empty
    @Published private(set) var activity: WorkoutActivity?
    @Published private(set) var isActive = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentInterval: IntervalWorkout?
    @Published private(set) var isStarting = false
    @Published private(set) var isFinishing = false
    @Published private(set) var startStatus: WorkoutStartStatus?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    private var startDate: Date?
    private var activeSegmentStartDate: Date?
    private var accumulatedActiveSeconds: TimeInterval = 0
    private var lastAcceptedLocationDate: Date?
    private var timer: Timer?
    private var distanceUnit: DistanceUnit = .miles
    private var paceMode: PaceMode = .rolling
    private var rollingPaceSeconds = 30
    private var lastPaceRefreshElapsedSeconds: TimeInterval?
    private var lastIntervalCueID: String?
    private let completionNotifier = WatchWorkoutCompletionNotifier()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func start(activity: WorkoutActivity) {
        beginStart(activity: activity, interval: nil)
    }

    func updateSettings(_ settings: WorkoutSettings) {
        let paceConfigurationChanged = distanceUnit != settings.distanceUnit ||
            paceMode != settings.paceMode ||
            rollingPaceSeconds != settings.rollingPaceSeconds
        distanceUnit = settings.distanceUnit
        paceMode = settings.paceMode
        rollingPaceSeconds = settings.rollingPaceSeconds
        if paceConfigurationChanged {
            lastPaceRefreshElapsedSeconds = nil
            updatePace(force: true)
        }
    }

    func startInterval(_ interval: IntervalWorkout) {
        beginStart(activity: .indoorRun, interval: interval)
    }

    func clearStartStatus() {
        startStatus = nil
    }

    func togglePause() {
        guard let session, !isFinishing else { return }
        if isPaused {
            session.resume()
            transitionToRunning(at: Date())
        } else {
            session.pause()
            transitionToPaused(at: Date())
        }
    }

    func end() {
        guard isActive, !isFinishing else { return }
        isFinishing = true
        snapshot.elapsedSeconds = activeElapsed(at: Date())
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
        guard let session else {
            resetSessionAfterFinish()
            return
        }
        session.end()
    }

    private func beginStart(activity: WorkoutActivity, interval: IntervalWorkout?) {
        guard !isStarting, !isActive else { return }
        self.activity = activity
        self.currentInterval = interval
        self.lastIntervalCueID = nil
        self.isFinishing = false
        isStarting = true
        startStatus = .starting("Requesting Health access")

        requestAuthorization(for: activity) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.startWorkout(activity: activity)
                case .failure(let error):
                    self.isStarting = false
                    self.isFinishing = false
                    self.currentInterval = nil
                    self.startStatus = .failure(error.localizedDescription)
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }

    private func startWorkout(activity: WorkoutActivity) {
        startStatus = .starting("Starting workout")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthKitType
        configuration.locationType = activity.environment == .outdoor ? .outdoor : .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            builder.addMetadata([
                HKMetadataKeyIndoorWorkout: activity.environment == .indoor
            ]) { _, _ in }
            self.session = session
            self.builder = builder

            if activity.environment == .outdoor {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                startOutdoorLocationUpdatesIfAvailable()
            }

            let start = Date()
            startDate = start
            activeSegmentStartDate = start
            accumulatedActiveSeconds = 0
            lastAcceptedLocationDate = nil
            lastPaceRefreshElapsedSeconds = nil
            lastIntervalCueID = initialIntervalCueID()
            snapshot = .empty
            isActive = true
            isStarting = false
            isFinishing = false
            isPaused = false
            if case .starting = startStatus {
                startStatus = nil
            }
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            startTimer()
        } catch {
            isStarting = false
            isFinishing = false
            isActive = false
            currentInterval = nil
            startStatus = .failure(error.localizedDescription)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func requestAuthorization(for activity: WorkoutActivity, completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(WorkoutStartError.healthDataUnavailable))
            return
        }

        let authorizationTypes = healthAuthorizationTypes(for: activity)

        healthStore.requestAuthorization(toShare: authorizationTypes.shareTypes, read: authorizationTypes.readTypes) { [weak self] success, error in
            guard let self else { return }
            guard success else {
                completion(.failure(error ?? WorkoutStartError.healthAuthorizationDenied(["Health access"])))
                return
            }

            let deniedTypes = authorizationTypes.requiredShareTypes.compactMap { type -> String? in
                self.healthStore.authorizationStatus(for: type.sampleType) == .sharingDenied ? type.displayName : nil
            }

            if deniedTypes.isEmpty {
                completion(.success(()))
            } else {
                completion(.failure(WorkoutStartError.healthAuthorizationDenied(deniedTypes)))
            }
        }
    }

    private func healthAuthorizationTypes(for activity: WorkoutActivity) -> HealthAuthorizationTypes {
        var readTypes = Set<HKObjectType>()
        var shareTypes = Set<HKSampleType>()
        var requiredShareTypes: [RequiredHealthShareType] = []

        let workoutType = HKObjectType.workoutType()
        readTypes.insert(workoutType)
        shareTypes.insert(workoutType)
        requiredShareTypes.append(RequiredHealthShareType(sampleType: workoutType, displayName: "Workouts"))

        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
            shareTypes.insert(activeEnergy)
            requiredShareTypes.append(RequiredHealthShareType(sampleType: activeEnergy, displayName: "Active Energy"))
        }
        if let walkingRunning = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            readTypes.insert(walkingRunning)
            if activity.distanceQuantityIdentifier == HKQuantityTypeIdentifier.distanceWalkingRunning {
                shareTypes.insert(walkingRunning)
                requiredShareTypes.append(RequiredHealthShareType(sampleType: walkingRunning, displayName: "Walking + Running Distance"))
            }
        }
        if let cycling = HKObjectType.quantityType(forIdentifier: .distanceCycling) {
            readTypes.insert(cycling)
            if activity.distanceQuantityIdentifier == HKQuantityTypeIdentifier.distanceCycling {
                shareTypes.insert(cycling)
                requiredShareTypes.append(RequiredHealthShareType(sampleType: cycling, displayName: "Cycling Distance"))
            }
        }
        let routeType = HKSeriesType.workoutRoute()
        readTypes.insert(routeType)
        if activity.environment == .outdoor {
            shareTypes.insert(routeType)
            requiredShareTypes.append(RequiredHealthShareType(sampleType: routeType, displayName: "Workout Routes"))
        }

        return HealthAuthorizationTypes(
            readTypes: readTypes,
            shareTypes: shareTypes,
            requiredShareTypes: requiredShareTypes
        )
    }

    private func startOutdoorLocationUpdatesIfAvailable() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            startStatus = .warning("Allow location for route recording")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            startStatus = .warning("Location is off, route will not be recorded")
            return
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        @unknown default:
            startStatus = .warning("Location permission is unknown")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isActive else { return }
            DispatchQueue.main.async {
                self.snapshot.elapsedSeconds = self.activeElapsed(at: Date())
                self.updatePace()
                self.updateIntervalCue()
            }
        }
    }

    private func activeElapsed(at date: Date) -> TimeInterval {
        let segmentSeconds = activeSegmentStartDate.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return accumulatedActiveSeconds + segmentSeconds
    }

    private func activeTimelineDate(for sampleDate: Date) -> Date {
        guard let startDate else { return sampleDate }
        return startDate.addingTimeInterval(activeElapsed(at: sampleDate))
    }

    private func transitionToPaused(at date: Date) {
        guard isActive, !isPaused else { return }
        accumulatedActiveSeconds = activeElapsed(at: date)
        activeSegmentStartDate = nil
        snapshot.elapsedSeconds = accumulatedActiveSeconds
        isPaused = true
        if activity?.environment == .outdoor {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
        }
        updatePace(force: true)
    }

    private func transitionToRunning(at date: Date) {
        guard isActive, isPaused else { return }
        activeSegmentStartDate = date
        isPaused = false
        if activity?.environment == .outdoor {
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        }
        snapshot.elapsedSeconds = activeElapsed(at: date)
        updatePace(force: true)
    }

    private func updatePace(force: Bool = false) {
        guard force || PaceCalculator.shouldRefreshDisplayedPace(
            elapsedSeconds: snapshot.elapsedSeconds,
            lastRefreshElapsedSeconds: lastPaceRefreshElapsedSeconds,
            mode: paceMode,
            rollingPaceSeconds: rollingPaceSeconds
        ) else {
            return
        }

        if activity?.environment == .outdoor {
            switch paceMode {
            case .rolling:
                snapshot.paceSecondsPerUnit = PaceCalculator.rollingPace(points: snapshot.route, windowSeconds: rollingPaceSeconds, unit: distanceUnit)
            case .wholeWorkout:
                let routeDistance = PaceCalculator.totalDistanceMeters(points: snapshot.route)
                snapshot.paceSecondsPerUnit = PaceCalculator.paceSecondsPerUnit(
                    distanceMeters: snapshot.distanceMeters > 0 ? snapshot.distanceMeters : routeDistance,
                    elapsedSeconds: snapshot.elapsedSeconds,
                    unit: distanceUnit
                )
            case .currentSplit:
                snapshot.paceSecondsPerUnit = PaceCalculator.currentSplitPace(points: snapshot.route, unit: distanceUnit)
            }
        } else {
            snapshot.paceSecondsPerUnit = PaceCalculator.paceSecondsPerUnit(distanceMeters: snapshot.distanceMeters, elapsedSeconds: snapshot.elapsedSeconds, unit: distanceUnit)
        }
        lastPaceRefreshElapsedSeconds = snapshot.elapsedSeconds
    }

    private func updateIntervalCue() {
        guard let currentInterval else { return }
        let progress = IntervalTimeline.progress(for: currentInterval, elapsedSeconds: snapshot.elapsedSeconds)
        let cueID = intervalCueID(for: progress)
        guard cueID != lastIntervalCueID else { return }
        lastIntervalCueID = cueID
        WKInterfaceDevice.current().play(progress.isComplete ? .success : .notification)
    }

    private func initialIntervalCueID() -> String? {
        guard let currentInterval else { return nil }
        return intervalCueID(for: IntervalTimeline.progress(for: currentInterval, elapsedSeconds: 0))
    }

    private func intervalCueID(for progress: IntervalProgress) -> String {
        "\(progress.stepIndex)-\(progress.isComplete)"
    }

    private func updateStatistics() {
        guard let builder else { return }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: type),
           let quantity = statistics.mostRecentQuantity() {
            snapshot.heartRate = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let statistics = builder.statistics(for: type),
           let quantity = statistics.sumQuantity() {
            snapshot.activeEnergyKilocalories = WorkoutCalories.activeKilocalories(fromHealthKitActiveKilocalories: quantity.doubleValue(for: .kilocalorie()))
        }

        guard let activity, activity.recordsDistance, let distanceIdentifier = activity.distanceQuantityIdentifier else {
            snapshot.distanceMeters = 0
            snapshot.paceSecondsPerUnit = nil
            return
        }

        if let type = HKQuantityType.quantityType(forIdentifier: distanceIdentifier),
           let statistics = builder.statistics(for: type),
           let quantity = statistics.sumQuantity() {
            snapshot.distanceMeters = quantity.doubleValue(for: .meter())
        }
    }

    private func finishWorkout() {
        let endedActivity = activity
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { workout, error in
                guard let self else { return }

                guard let workout else {
                    DispatchQueue.main.async {
                        if let error {
                            self.startStatus = .failure(error.localizedDescription)
                        }
                        self.resetSessionAfterFinish()
                    }
                    return
                }

                let notifyAndReset = {
                    self.completionNotifier.notifyWorkoutFinished(workout: workout, activity: endedActivity)
                    DispatchQueue.main.async {
                        self.resetSessionAfterFinish()
                    }
                }

                guard let routeBuilder = self.routeBuilder else {
                    notifyAndReset()
                    return
                }

                routeBuilder.finishRoute(with: workout, metadata: nil) { _, routeError in
                    if routeError != nil {
                        DispatchQueue.main.async {
                            self.startStatus = .warning("Route save failed; workout was saved.")
                        }
                    }
                    notifyAndReset()
                }
            }
        }
    }

    private func resetSessionAfterFinish() {
        isActive = false
        isStarting = false
        isFinishing = false
        isPaused = false
        startDate = nil
        activeSegmentStartDate = nil
        accumulatedActiveSeconds = 0
        lastAcceptedLocationDate = nil
        lastPaceRefreshElapsedSeconds = nil
        lastIntervalCueID = nil
        session = nil
        builder = nil
        routeBuilder = nil
        currentInterval = nil
    }
}

private final class WatchWorkoutCompletionNotifier {
    func notifyWorkoutFinished(workout: HKWorkout, activity: WorkoutActivity?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [
            WatchConnectivityPayloadKey.workoutFinished: true,
            WatchConnectivityPayloadKey.workoutID: workout.uuid.uuidString,
            WatchConnectivityPayloadKey.activity: activity?.rawValue ?? "",
            WatchConnectivityPayloadKey.endedAt: workout.endDate
        ]

        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else if session.activationState == .activated {
            session.transferUserInfo(payload)
        }
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch toState {
            case .paused:
                self.transitionToPaused(at: date)
            case .running:
                if fromState == .paused {
                    self.transitionToRunning(at: date)
                }
            case .ended:
                self.snapshot.elapsedSeconds = self.activeElapsed(at: date)
                self.finishWorkout()
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isStarting = false
            self.isFinishing = false
            self.isActive = false
            self.startStatus = .failure(error.localizedDescription)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        DispatchQueue.main.async {
            self.updateStatistics()
        }
    }
}

extension WorkoutSessionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, !isPaused, let activeSegmentStartDate else { return }
        let accepted = locations.filter { location in
            location.horizontalAccuracy >= 0 &&
                location.horizontalAccuracy <= 50 &&
                location.timestamp >= activeSegmentStartDate &&
                (lastAcceptedLocationDate == nil || location.timestamp > lastAcceptedLocationDate!)
        }
        guard !accepted.isEmpty else { return }

        routeBuilder?.insertRouteData(accepted) { _, _ in }

        DispatchQueue.main.async {
            let points = accepted.map {
                RoutePoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    altitudeMeters: $0.altitude,
                    timestamp: self.activeTimelineDate(for: $0.timestamp),
                    horizontalAccuracy: $0.horizontalAccuracy
                )
            }
            self.lastAcceptedLocationDate = accepted.last?.timestamp
            self.snapshot.route.append(contentsOf: points)
            if self.snapshot.distanceMeters == 0 {
                self.snapshot.distanceMeters = PaceCalculator.totalDistanceMeters(points: self.snapshot.route)
            }
            if let course = accepted.last?.course, course >= 0 {
                self.snapshot.headingDegrees = course
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            self.snapshot.headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            guard self.activity?.environment == .outdoor else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.isActive, !self.isPaused {
                    manager.startUpdatingLocation()
                    if CLLocationManager.headingAvailable() {
                        manager.startUpdatingHeading()
                    }
                }
                if case .warning = self.startStatus {
                    self.startStatus = nil
                }
            case .restricted, .denied:
                self.startStatus = .warning("Location is off, route will not be recorded")
            case .notDetermined:
                break
            @unknown default:
                self.startStatus = .warning("Location permission is unknown")
            }
        }
    }
}

private extension WorkoutActivity {
    var distanceQuantityIdentifier: HKQuantityTypeIdentifier? {
        guard recordsDistance else { return nil }
        switch self {
        case .outdoorBike, .indoorBike:
            return .distanceCycling
        default:
            return .distanceWalkingRunning
        }
    }

    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .outdoorRun, .indoorRun:
            return .running
        case .outdoorWalk, .indoorWalk:
            return .walking
        case .outdoorBike, .indoorBike:
            return .cycling
        case .indoorElliptical:
            return .elliptical
        case .weights:
            return .traditionalStrengthTraining
        }
    }
}

private struct HealthAuthorizationTypes {
    var readTypes: Set<HKObjectType>
    var shareTypes: Set<HKSampleType>
    var requiredShareTypes: [RequiredHealthShareType]
}

private struct RequiredHealthShareType {
    var sampleType: HKSampleType
    var displayName: String
}

private enum WorkoutStartError: LocalizedError {
    case healthDataUnavailable
    case healthAuthorizationDenied([String])

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this Apple Watch."
        case .healthAuthorizationDenied(let names):
            return "Enable Health write access for \(names.joined(separator: ", "))."
        }
    }
}
