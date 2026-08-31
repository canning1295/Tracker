import AVFoundation
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

struct WatchWorkoutCompletionSummary: Identifiable, Equatable {
    enum SaveState: Equatable {
        case saving
        case saved
        case failed(String)
    }

    var id: UUID
    var activity: WorkoutActivity?
    var elapsedSeconds: TimeInterval
    var distanceMeters: Double
    var distanceIsEstimated: Bool
    var activeEnergyKilocalories: Double
    var saveState: SaveState
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
    @Published private(set) var completedWorkoutSummary: WatchWorkoutCompletionSummary?
    @Published private(set) var gpsReadiness: GPSReadiness = .checking

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    private var startDate: Date?
    private var endDecisionDate: Date?
    private var activeSegmentStartDate: Date?
    private var accumulatedActiveSeconds: TimeInterval = 0
    private var lastAcceptedLocationDate: Date?
    private var lastGPSFixDate: Date?
    private var lastGPSAccuracyMeters: Double?
    private var shouldAcquireLocation = false
    private var gpsReadinessTimer: Timer?
    private var hasLiveHealthKitDistance = false
    private var didAddEstimatedDistanceSample = false
    private var lastIndoorEstimateElapsedSeconds: TimeInterval = 0
    private var timer: Timer?
    private var distanceUnit: DistanceUnit = .miles
    private var splitAnnouncementUnit: WorkoutAnnouncementUnit = .miles
    private var activeSplitAnnouncementUnit: DistanceUnit?
    private var splitAnnouncementTracker = DistanceSplitAnnouncementTracker()
    private var paceMode: PaceMode = .rolling
    private var rollingPaceSeconds = 30
    private var heartRateSettings = WorkoutSettings.defaults.heartRate
    private var restingHeartRate: Int?
    private var lastPaceRefreshElapsedSeconds: TimeInterval?
    private var lastIntervalCueID: String?
    private var pendingTrimEndSeconds: TimeInterval = 0
    private var pendingTrimmedDistanceMeters: Double?
    private let announcementSpeaker = WorkoutAnnouncementSpeaker()
    private let completionOutbox = WatchWorkoutCompletionOutbox()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func start(activity: WorkoutActivity) {
        beginStart(activity: activity, interval: nil)
    }

    func beginLocationAcquisition() {
        shouldAcquireLocation = true

        guard CLLocationManager.locationServicesEnabled() else {
            gpsReadiness = .unavailable("Location Services are off")
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            gpsReadiness = .requestingPermission
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            gpsReadiness = .unavailable("Location access is off")
        case .authorizedAlways, .authorizedWhenInUse:
            refreshGPSReadinessForAcquisition()
            if !isActive || (activity?.environment == .outdoor && !isPaused) {
                locationManager.startUpdatingLocation()
            }
            startGPSReadinessTimer()
        @unknown default:
            gpsReadiness = .unavailable("Location permission is unavailable")
        }
    }

    func stopPreworkoutLocationAcquisition() {
        guard !isActive else { return }
        shouldAcquireLocation = false
        locationManager.stopUpdatingLocation()
        gpsReadinessTimer?.invalidate()
        gpsReadinessTimer = nil
    }

    func updateSettings(_ settings: WorkoutSettings) {
        let paceConfigurationChanged = distanceUnit != settings.distanceUnit ||
            paceMode != settings.paceMode ||
            rollingPaceSeconds != settings.rollingPaceSeconds
        distanceUnit = settings.distanceUnit
        splitAnnouncementUnit = settings.splitAnnouncementUnit
        paceMode = settings.paceMode
        rollingPaceSeconds = settings.rollingPaceSeconds
        heartRateSettings = settings.heartRate
        restingHeartRate = settings.userMetrics.restingHeartRate
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

    func dismissCompletedWorkoutSummary() {
        guard completedWorkoutSummary?.saveState != .saving else { return }
        completedWorkoutSummary = nil
        activity = nil
        snapshot = .empty
        beginLocationAcquisition()
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

    func beginEndConfirmation() -> Bool {
        guard isActive, !isFinishing else { return false }
        let wasRunning = !isPaused
        let confirmationDate = Date()
        endDecisionDate = confirmationDate
        if wasRunning {
            session?.pause()
            transitionToPaused(at: confirmationDate)
        }
        return wasRunning
    }

    func cancelEndConfirmation(resumeWorkout: Bool) {
        guard isActive, !isFinishing else { return }
        endDecisionDate = nil
        guard resumeWorkout, isPaused else { return }
        let resumeDate = Date()
        session?.resume()
        transitionToRunning(at: resumeDate)
    }

    func prepareToEnd() -> WorkoutEndTrimSuggestion? {
        guard isActive, !isFinishing else { return nil }
        isFinishing = true
        let decisionDate = endDecisionDate ?? Date()
        endDecisionDate = decisionDate
        snapshot.elapsedSeconds = activeElapsed(at: Date())
        if !isPaused {
            session?.pause()
            transitionToPaused(at: decisionDate)
        }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        shouldAcquireLocation = false
        gpsReadinessTimer?.invalidate()
        gpsReadinessTimer = nil
        timer?.invalidate()
        timer = nil

        guard activity?.environment == .outdoor,
              let startDate else {
            return nil
        }
        return WorkoutEndAnomalyDetector.suggestion(
            route: snapshot.route,
            workoutEnd: startDate.addingTimeInterval(snapshot.elapsedSeconds)
        )
    }

    func finishEnd(trimSuggestion: WorkoutEndTrimSuggestion? = nil) {
        guard isActive, isFinishing else { return }
        let maximumTrim = max(0, snapshot.elapsedSeconds - 60)
        pendingTrimEndSeconds = min(max(0, trimSuggestion?.trimEndSeconds ?? 0), maximumTrim)
        pendingTrimmedDistanceMeters = pendingTrimEndSeconds > 0 ? trimSuggestion?.retainedDistanceMeters : nil
        presentCompletionSummaryIfNeeded(activity: activity)
        guard let session else {
            failFinishedWorkout("Workout session data was unavailable.")
            return
        }
        session.end()
    }

    var liveSessionStatus: WatchLiveSessionStatus? {
        guard isActive, let activity else { return nil }
        return WatchLiveSessionStatus(
            activity: activity,
            isPaused: isPaused,
            isFinishing: isFinishing,
            elapsedSeconds: snapshot.elapsedSeconds,
            distanceMeters: snapshot.distanceMeters
        )
    }

    /// Applies a control sent from the phone or the Action Button. A remote end
    /// keeps every recorded second: auto-trim is a judgement for someone looking
    /// at the summary, not something to apply from a button press.
    func applyRemoteCommand(_ command: WatchWorkoutRemoteCommand) {
        guard isActive, !isFinishing else { return }
        switch command {
        case .togglePause:
            togglePause()
        case .pause:
            guard !isPaused else { return }
            togglePause()
        case .resume:
            guard isPaused else { return }
            togglePause()
        case .end:
            _ = prepareToEnd()
            finishEnd()
        }
    }

    private func beginStart(activity: WorkoutActivity, interval: IntervalWorkout?) {
        guard !isStarting, !isActive, completedWorkoutSummary == nil else { return }
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
                gpsReadinessTimer?.invalidate()
                gpsReadinessTimer = nil
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                startOutdoorLocationUpdatesIfAvailable()
            } else {
                shouldAcquireLocation = false
                locationManager.stopUpdatingLocation()
                locationManager.stopUpdatingHeading()
                gpsReadinessTimer?.invalidate()
                gpsReadinessTimer = nil
            }

            let start = Date()
            startDate = start
            endDecisionDate = nil
            activeSegmentStartDate = start
            accumulatedActiveSeconds = 0
            lastAcceptedLocationDate = nil
            hasLiveHealthKitDistance = false
            didAddEstimatedDistanceSample = false
            lastIndoorEstimateElapsedSeconds = 0
            lastPaceRefreshElapsedSeconds = nil
            lastIntervalCueID = initialIntervalCueID()
            activeSplitAnnouncementUnit = splitAnnouncementUnit.distanceUnit
            splitAnnouncementTracker.reset()
            pendingTrimEndSeconds = 0
            pendingTrimmedDistanceMeters = nil
            snapshot = .empty
            snapshot.distanceIsEstimated = activity.environment == .indoor &&
                IndoorDistanceEstimator.anchorPaceMinutesPerMile(for: activity) != nil
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
        shouldAcquireLocation = true
        switch locationManager.authorizationStatus {
        case .notDetermined:
            startStatus = .warning("Allow location for route recording")
            gpsReadiness = .requestingPermission
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            startStatus = .warning("Location is off, route will not be recorded")
            gpsReadiness = .unavailable("Location access is off")
            return
        case .authorizedAlways, .authorizedWhenInUse:
            refreshGPSReadinessForAcquisition()
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        @unknown default:
            startStatus = .warning("Location permission is unknown")
            gpsReadiness = .unavailable("Location permission is unavailable")
        }
    }

    private func refreshGPSReadinessForAcquisition() {
        guard let lastGPSFixDate,
              Date().timeIntervalSince(lastGPSFixDate) <= 15 else {
            gpsReadiness = .acquiring(accuracyMeters: nil)
            return
        }
        gpsReadiness = .measured(horizontalAccuracy: lastGPSAccuracyMeters)
    }

    private func startGPSReadinessTimer() {
        gpsReadinessTimer?.invalidate()
        guard !isActive else { return }
        gpsReadinessTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.shouldAcquireLocation, !self.isActive else { return }
            DispatchQueue.main.async {
                self.refreshGPSReadinessForAcquisition()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isActive else { return }
            DispatchQueue.main.async {
                let elapsedSeconds = self.activeElapsed(at: Date())
                self.snapshot.elapsedSeconds = elapsedSeconds
                self.updateIndoorDistanceEstimate(elapsedSeconds: elapsedSeconds)
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
            snapshot.distanceIsEstimated = false
            snapshot.paceSecondsPerUnit = nil
            return
        }

        if let type = HKQuantityType.quantityType(forIdentifier: distanceIdentifier),
           let statistics = builder.statistics(for: type),
           let quantity = statistics.sumQuantity() {
            let measuredDistanceMeters = quantity.doubleValue(for: .meter())
            if measuredDistanceMeters > 0, !didAddEstimatedDistanceSample {
                hasLiveHealthKitDistance = true
                snapshot.distanceMeters = measuredDistanceMeters
                snapshot.distanceIsEstimated = false
            }
        }
        updateDistanceAnnouncements()
    }

    private func updateIndoorDistanceEstimate(elapsedSeconds: TimeInterval) {
        guard let activity,
              activity.environment == .indoor,
              activity.recordsDistance,
              !hasLiveHealthKitDistance,
              !didAddEstimatedDistanceSample,
              let heartRate = snapshot.heartRate else {
            return
        }

        let additionalSeconds = max(0, elapsedSeconds - lastIndoorEstimateElapsedSeconds)
        guard additionalSeconds > 0 else { return }
        lastIndoorEstimateElapsedSeconds = elapsedSeconds
        snapshot.distanceMeters += IndoorDistanceEstimator.estimatedDistanceMeters(
            activity: activity,
            elapsedSeconds: additionalSeconds,
            averageHeartRate: heartRate,
            heartRateSettings: heartRateSettings,
            restingHeartRate: restingHeartRate
        )
        snapshot.distanceIsEstimated = true
        updateDistanceAnnouncements()
    }

    private func updateDistanceAnnouncements() {
        guard isActive,
              !isPaused,
              !isFinishing,
              activity?.recordsDistance == true,
              let unit = activeSplitAnnouncementUnit else {
            return
        }

        let announcements = splitAnnouncementTracker.announcements(
            distanceMeters: snapshot.distanceMeters,
            elapsedSeconds: activeElapsed(at: Date()),
            unit: unit
        )
        announcements.forEach { announcementSpeaker.speak($0.spokenText) }
    }

    private func finishWorkout() {
        let endedActivity = activity
        presentCompletionSummaryIfNeeded(activity: endedActivity)

        guard let builder else {
            failFinishedWorkout("Workout data was unavailable.")
            return
        }

        let collectionEndDate = endDecisionDate ?? Date()
        addEstimatedDistanceSampleIfNeeded(
            to: builder,
            collectionEndDate: collectionEndDate
        ) { [weak self] in
            self?.endCollection(
                builder,
                collectionEndDate: collectionEndDate,
                endedActivity: endedActivity
            )
        }
    }

    private func addEstimatedDistanceSampleIfNeeded(
        to builder: HKLiveWorkoutBuilder,
        collectionEndDate: Date,
        completion: @escaping () -> Void
    ) {
        guard snapshot.distanceIsEstimated,
              snapshot.distanceMeters > 0,
              let activity,
              let startDate,
              let distanceIdentifier = activity.distanceQuantityIdentifier,
              let distanceType = HKQuantityType.quantityType(forIdentifier: distanceIdentifier) else {
            completion()
            return
        }

        didAddEstimatedDistanceSample = true
        let sample = HKQuantitySample(
            type: distanceType,
            quantity: HKQuantity(unit: .meter(), doubleValue: snapshot.distanceMeters),
            start: startDate,
            end: collectionEndDate,
            metadata: [
                "com.toby.Tracker.distanceEstimated": true,
                "com.toby.Tracker.distanceAnchorHeartRate": IndoorDistanceEstimator.personalAnchorHeartRate
            ]
        )
        builder.add([sample]) { [weak self] success, _ in
            if !success {
                DispatchQueue.main.async {
                    self?.didAddEstimatedDistanceSample = false
                }
            }
            completion()
        }
    }

    private func endCollection(
        _ builder: HKLiveWorkoutBuilder,
        collectionEndDate: Date,
        endedActivity: WorkoutActivity?
    ) {
        builder.endCollection(withEnd: collectionEndDate) { [weak self] success, error in
            guard let self else { return }
            guard success else {
                self.failFinishedWorkout(error?.localizedDescription ?? "HealthKit could not finish collecting the workout.")
                return
            }

            builder.finishWorkout { workout, error in
                guard let workout else {
                    self.failFinishedWorkout(error?.localizedDescription ?? "HealthKit did not return a saved workout.")
                    return
                }

                let completeAndReset = {
                    self.completeFinishedWorkout(workout, activity: endedActivity)
                }

                guard let routeBuilder = self.routeBuilder else {
                    completeAndReset()
                    return
                }

                routeBuilder.finishRoute(with: workout, metadata: nil) { _, routeError in
                    if routeError != nil {
                        DispatchQueue.main.async {
                            self.startStatus = .warning("Route save failed; workout was saved.")
                        }
                    }
                    completeAndReset()
                }
            }
        }
    }

    private func completeFinishedWorkout(_ workout: HKWorkout, activity: WorkoutActivity?) {
        DispatchQueue.main.async {
            let completion = WatchWorkoutCompletion(
                workoutID: workout.uuid,
                activity: activity,
                endedAt: workout.endDate,
                trimEndSeconds: self.pendingTrimEndSeconds
            )
            self.completionOutbox.enqueue(completion)
            if WCSession.isSupported() {
                self.completionOutbox.flush(on: WCSession.default)
            }

            self.presentCompletionSummaryIfNeeded(activity: activity)
            self.completedWorkoutSummary?.saveState = .saved
            self.resetSessionAfterFinish()
            WKInterfaceDevice.current().play(.success)
        }
    }

    private func presentCompletionSummaryIfNeeded(activity: WorkoutActivity?) {
        let elapsedSeconds = max(0, snapshot.elapsedSeconds - pendingTrimEndSeconds)
        let durationRatio = snapshot.elapsedSeconds > 0
            ? min(max(elapsedSeconds / snapshot.elapsedSeconds, 0), 1)
            : 0
        let distanceMeters = pendingTrimmedDistanceMeters ?? snapshot.distanceMeters
        let activeEnergyKilocalories = snapshot.activeEnergyKilocalories * durationRatio

        if completedWorkoutSummary == nil {
            completedWorkoutSummary = WatchWorkoutCompletionSummary(
                id: UUID(),
                activity: activity,
                elapsedSeconds: elapsedSeconds,
                distanceMeters: distanceMeters,
                distanceIsEstimated: snapshot.distanceIsEstimated,
                activeEnergyKilocalories: activeEnergyKilocalories,
                saveState: .saving
            )
        } else {
            completedWorkoutSummary?.activity = activity
            completedWorkoutSummary?.elapsedSeconds = elapsedSeconds
            completedWorkoutSummary?.distanceMeters = distanceMeters
            completedWorkoutSummary?.distanceIsEstimated = snapshot.distanceIsEstimated
            completedWorkoutSummary?.activeEnergyKilocalories = activeEnergyKilocalories
        }
    }

    private func failFinishedWorkout(_ message: String) {
        DispatchQueue.main.async {
            guard self.completedWorkoutSummary?.saveState != .saved else { return }
            self.presentCompletionSummaryIfNeeded(activity: self.activity)
            self.completedWorkoutSummary?.saveState = .failed(message)
            self.resetSessionAfterFinish()
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func resetSessionAfterFinish() {
        isActive = false
        isStarting = false
        isFinishing = false
        isPaused = false
        startDate = nil
        endDecisionDate = nil
        activeSegmentStartDate = nil
        accumulatedActiveSeconds = 0
        lastAcceptedLocationDate = nil
        hasLiveHealthKitDistance = false
        didAddEstimatedDistanceSample = false
        lastIndoorEstimateElapsedSeconds = 0
        lastPaceRefreshElapsedSeconds = nil
        lastIntervalCueID = nil
        pendingTrimEndSeconds = 0
        pendingTrimmedDistanceMeters = nil
        activeSplitAnnouncementUnit = nil
        splitAnnouncementTracker.reset()
        session = nil
        builder = nil
        routeBuilder = nil
        currentInterval = nil
    }
}

private final class WorkoutAnnouncementSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var pendingUtteranceCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [])
            try audioSession.setActive(true)
        } catch {
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        pendingUtteranceCount += 1
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.finishUtterance()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.finishUtterance()
        }
    }

    private func finishUtterance() {
        pendingUtteranceCount = max(0, pendingUtteranceCount - 1)
        guard pendingUtteranceCount == 0 else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
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
                self.presentCompletionSummaryIfNeeded(activity: self.activity)
                self.finishWorkout()
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if self.isFinishing || self.completedWorkoutSummary != nil {
                self.failFinishedWorkout(error.localizedDescription)
                return
            }
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
        if let latestLocation = locations
            .filter({ $0.horizontalAccuracy.isFinite && $0.horizontalAccuracy >= 0 })
            .max(by: { $0.timestamp < $1.timestamp }) {
            DispatchQueue.main.async {
                guard self.shouldAcquireLocation || self.activity?.environment == .outdoor else { return }
                self.lastGPSFixDate = latestLocation.timestamp
                self.lastGPSAccuracyMeters = latestLocation.horizontalAccuracy
                self.gpsReadiness = .measured(horizontalAccuracy: latestLocation.horizontalAccuracy)
            }
        }

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
            if !self.hasLiveHealthKitDistance {
                self.snapshot.distanceMeters = PaceCalculator.totalDistanceMeters(points: self.snapshot.route)
            }
            if let course = accepted.last?.course, course >= 0 {
                self.snapshot.headingDegrees = course
            }
            self.updateDistanceAnnouncements()
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
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.shouldAcquireLocation || (self.activity?.environment == .outdoor && self.isActive && !self.isPaused) {
                    self.refreshGPSReadinessForAcquisition()
                    manager.startUpdatingLocation()
                    if !self.isActive {
                        self.startGPSReadinessTimer()
                    }
                }
                if self.activity?.environment == .outdoor, self.isActive, !self.isPaused {
                    if CLLocationManager.headingAvailable() {
                        manager.startUpdatingHeading()
                    }
                }
                if case .warning = self.startStatus {
                    self.startStatus = nil
                }
            case .restricted, .denied:
                self.gpsReadiness = .unavailable("Location access is off")
                if self.activity?.environment == .outdoor {
                    self.startStatus = .warning("Location is off, route will not be recorded")
                }
            case .notDetermined:
                if self.shouldAcquireLocation {
                    self.gpsReadiness = .requestingPermission
                }
                break
            @unknown default:
                self.gpsReadiness = .unavailable("Location permission is unavailable")
                if self.activity?.environment == .outdoor {
                    self.startStatus = .warning("Location permission is unknown")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard self.shouldAcquireLocation || self.activity?.environment == .outdoor else { return }
            if let locationError = error as? CLError, locationError.code == .denied {
                self.gpsReadiness = .unavailable("Location access is off")
            } else {
                self.gpsReadiness = .acquiring(accuracyMeters: nil)
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
