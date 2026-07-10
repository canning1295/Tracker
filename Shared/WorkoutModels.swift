import Foundation

enum ActivityEnvironment: String, Codable, CaseIterable, Identifiable, Hashable {
    case outdoor
    case indoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outdoor: return "Outdoor"
        case .indoor: return "Indoor"
        }
    }
}

enum WorkoutActivity: String, Codable, CaseIterable, Identifiable, Hashable {
    case outdoorRun
    case outdoorWalk
    case outdoorBike
    case indoorRun
    case indoorWalk
    case indoorElliptical
    case indoorBike
    case weights

    var id: String { rawValue }

    var environment: ActivityEnvironment {
        switch self {
        case .outdoorRun, .outdoorWalk, .outdoorBike:
            return .outdoor
        case .indoorRun, .indoorWalk, .indoorElliptical, .indoorBike, .weights:
            return .indoor
        }
    }

    var displayName: String {
        switch self {
        case .outdoorRun, .indoorRun: return "Run"
        case .outdoorWalk, .indoorWalk: return "Walk"
        case .outdoorBike, .indoorBike: return "Bike"
        case .indoorElliptical: return "Elliptical"
        case .weights: return "Weights"
        }
    }

    var symbolName: String {
        switch self {
        case .outdoorRun, .indoorRun: return "figure.run"
        case .outdoorWalk, .indoorWalk: return "figure.walk"
        case .outdoorBike, .indoorBike: return "bicycle"
        case .indoorElliptical: return "figure.elliptical"
        case .weights: return "dumbbell"
        }
    }

    var recordsDistance: Bool {
        self != .weights
    }

    var supportsPace: Bool {
        recordsDistance
    }

    static let defaultOutdoorOrder: [WorkoutActivity] = [.outdoorRun, .outdoorWalk, .outdoorBike]
    static let defaultIndoorOrder: [WorkoutActivity] = [.indoorRun, .indoorWalk, .indoorElliptical, .indoorBike, .weights]
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    var shortName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    var singularName: String {
        switch self {
        case .miles: return "mile"
        case .kilometers: return "kilometer"
        }
    }

    var metersPerUnit: Double {
        switch self {
        case .miles: return 1609.344
        case .kilometers: return 1000
        }
    }
}

enum BestEffortDistance: String, CaseIterable, Identifiable, Hashable {
    case meters100
    case meters200
    case meters400
    case kilometer
    case mile
    case fiveKilometers
    case tenKilometers
    case halfMarathon
    case marathon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meters100: return "100 m"
        case .meters200: return "200 m"
        case .meters400: return "400 m"
        case .kilometer: return "1 km"
        case .mile: return "1 mile"
        case .fiveKilometers: return "5K"
        case .tenKilometers: return "10K"
        case .halfMarathon: return "Half Marathon"
        case .marathon: return "Marathon"
        }
    }

    var meters: Double {
        switch self {
        case .meters100: return 100
        case .meters200: return 200
        case .meters400: return 400
        case .kilometer: return 1_000
        case .mile: return DistanceUnit.miles.metersPerUnit
        case .fiveKilometers: return 5_000
        case .tenKilometers: return 10_000
        case .halfMarathon: return 21_097.5
        case .marathon: return 42_195
        }
    }
}

enum WorkoutAnnouncementUnit: String, Codable, CaseIterable, Identifiable {
    case off
    case miles
    case kilometers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "None"
        case .miles: return "Mile"
        case .kilometers: return "Kilometer"
        }
    }

    var distanceUnit: DistanceUnit? {
        switch self {
        case .off: return nil
        case .miles: return .miles
        case .kilometers: return .kilometers
        }
    }

    init(distanceUnit: DistanceUnit) {
        switch distanceUnit {
        case .miles: self = .miles
        case .kilometers: self = .kilometers
        }
    }
}

enum BodyMeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric: return "Metric"
        }
    }
}

enum PaceMode: String, Codable, CaseIterable, Identifiable {
    case rolling
    case wholeWorkout
    case currentSplit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rolling: return "Rolling"
        case .wholeWorkout: return "Whole workout"
        case .currentSplit: return "Current split"
        }
    }
}

struct WorkoutSettings: Codable, Equatable {
    var distanceUnit: DistanceUnit
    var splitAnnouncementUnit: WorkoutAnnouncementUnit
    var bodyMeasurementUnit: BodyMeasurementUnit
    var paceMode: PaceMode
    var rollingPaceSeconds: Int
    var touchControlsEnabled: Bool
    var autoDisableTouchOnWorkoutStart: Bool
    var outdoorOrder: [WorkoutActivity]
    var indoorOrder: [WorkoutActivity]
    var heartRate: HeartRateSettings
    var userMetrics: UserMetrics
    var stravaAutoUpload: Bool

    static let defaults = WorkoutSettings(
        distanceUnit: .miles,
        splitAnnouncementUnit: .miles,
        bodyMeasurementUnit: .imperial,
        paceMode: .rolling,
        rollingPaceSeconds: 30,
        touchControlsEnabled: true,
        autoDisableTouchOnWorkoutStart: true,
        outdoorOrder: WorkoutActivity.defaultOutdoorOrder,
        indoorOrder: WorkoutActivity.defaultIndoorOrder,
        heartRate: HeartRateSettings(maxHeartRate: 190),
        userMetrics: UserMetrics(),
        stravaAutoUpload: true
    )

    init(
        distanceUnit: DistanceUnit,
        splitAnnouncementUnit: WorkoutAnnouncementUnit = .miles,
        bodyMeasurementUnit: BodyMeasurementUnit = .imperial,
        paceMode: PaceMode,
        rollingPaceSeconds: Int,
        touchControlsEnabled: Bool = true,
        autoDisableTouchOnWorkoutStart: Bool = true,
        outdoorOrder: [WorkoutActivity],
        indoorOrder: [WorkoutActivity],
        heartRate: HeartRateSettings,
        userMetrics: UserMetrics,
        stravaAutoUpload: Bool
    ) {
        self.distanceUnit = distanceUnit
        self.splitAnnouncementUnit = splitAnnouncementUnit
        self.bodyMeasurementUnit = bodyMeasurementUnit
        self.paceMode = paceMode
        self.rollingPaceSeconds = rollingPaceSeconds
        self.touchControlsEnabled = touchControlsEnabled
        self.autoDisableTouchOnWorkoutStart = autoDisableTouchOnWorkoutStart
        self.outdoorOrder = outdoorOrder
        self.indoorOrder = indoorOrder
        self.heartRate = heartRate
        self.userMetrics = userMetrics
        self.stravaAutoUpload = stravaAutoUpload
    }

    enum CodingKeys: String, CodingKey {
        case distanceUnit
        case splitAnnouncementUnit
        case bodyMeasurementUnit
        case paceMode
        case rollingPaceSeconds
        case touchControlsEnabled
        case autoDisableTouchOnWorkoutStart
        case outdoorOrder
        case indoorOrder
        case heartRate
        case userMetrics
        case stravaAutoUpload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distanceUnit = try container.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? .miles
        splitAnnouncementUnit = try container.decodeIfPresent(WorkoutAnnouncementUnit.self, forKey: .splitAnnouncementUnit)
            ?? WorkoutAnnouncementUnit(distanceUnit: distanceUnit)
        bodyMeasurementUnit = try container.decodeIfPresent(BodyMeasurementUnit.self, forKey: .bodyMeasurementUnit) ?? .imperial
        paceMode = try container.decodeIfPresent(PaceMode.self, forKey: .paceMode) ?? .rolling
        rollingPaceSeconds = try container.decodeIfPresent(Int.self, forKey: .rollingPaceSeconds) ?? 30
        touchControlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .touchControlsEnabled) ?? true
        autoDisableTouchOnWorkoutStart = try container.decodeIfPresent(Bool.self, forKey: .autoDisableTouchOnWorkoutStart) ?? true
        outdoorOrder = try container.decodeIfPresent([WorkoutActivity].self, forKey: .outdoorOrder) ?? WorkoutActivity.defaultOutdoorOrder
        indoorOrder = try container.decodeIfPresent([WorkoutActivity].self, forKey: .indoorOrder) ?? WorkoutActivity.defaultIndoorOrder
        heartRate = try container.decodeIfPresent(HeartRateSettings.self, forKey: .heartRate) ?? HeartRateSettings(maxHeartRate: 190)
        userMetrics = try container.decodeIfPresent(UserMetrics.self, forKey: .userMetrics) ?? UserMetrics()
        stravaAutoUpload = try container.decodeIfPresent(Bool.self, forKey: .stravaAutoUpload) ?? true
    }
}

struct WorkoutControlPresentation: Equatable {
    var statusText: String?
    var pauseTitle: String
    var pauseSystemImage: String
    var isPauseEnabled: Bool
    var endTitle: String
    var endSystemImage: String
    var isEndEnabled: Bool

    init(isPaused: Bool, isFinishing: Bool) {
        statusText = isFinishing ? "Saving" : (isPaused ? "Paused" : nil)
        pauseTitle = isPaused ? "Resume" : "Pause"
        pauseSystemImage = isPaused ? "play.fill" : "pause.fill"
        isPauseEnabled = !isFinishing
        endTitle = isFinishing ? "Saving" : "End"
        endSystemImage = isFinishing ? "hourglass" : "stop.fill"
        isEndEnabled = !isFinishing
    }
}

struct HeartRateSettings: Codable, Equatable {
    var maxHeartRate: Int
    var zoneBoundaries: [Double]

    init(maxHeartRate: Int, zoneBoundaries: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90]) {
        self.maxHeartRate = maxHeartRate
        self.zoneBoundaries = zoneBoundaries
    }
}

struct UserMetrics: Codable, Equatable {
    var age: Int?
    var biologicalSex: BiologicalSex?
    var heightCentimeters: Double?
    var weightKilograms: Double?
    var restingHeartRate: Int?
    var knownVO2Max: Double?

    init(
        age: Int? = nil,
        biologicalSex: BiologicalSex? = nil,
        heightCentimeters: Double? = nil,
        weightKilograms: Double? = nil,
        restingHeartRate: Int? = nil,
        knownVO2Max: Double? = nil
    ) {
        self.age = age
        self.biologicalSex = biologicalSex
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.restingHeartRate = restingHeartRate
        self.knownVO2Max = knownVO2Max
    }

    enum CodingKeys: String, CodingKey {
        case age
        case biologicalSex
        case heightCentimeters
        case weightKilograms
        case restingHeartRate
        case knownVO2Max
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        biologicalSex = try container.decodeIfPresent(BiologicalSex.self, forKey: .biologicalSex)
        heightCentimeters = try container.decodeIfPresent(Double.self, forKey: .heightCentimeters)
        weightKilograms = try container.decodeIfPresent(Double.self, forKey: .weightKilograms)
        restingHeartRate = try container.decodeIfPresent(Int.self, forKey: .restingHeartRate)
        knownVO2Max = try container.decodeIfPresent(Double.self, forKey: .knownVO2Max)
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case female
    case male
    case other
    case notSet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        case .notSet: return "Not set"
        }
    }
}

struct IntervalWorkout: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var warmupSeconds: Int
    var repeats: Int
    var work: IntervalStep
    var recovery: IntervalStep
    var cooldownSeconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        warmupSeconds: Int,
        repeats: Int,
        work: IntervalStep,
        recovery: IntervalStep,
        cooldownSeconds: Int
    ) {
        self.id = id
        self.name = name
        self.warmupSeconds = warmupSeconds
        self.repeats = repeats
        self.work = work
        self.recovery = recovery
        self.cooldownSeconds = cooldownSeconds
    }

    var totalSeconds: Int {
        warmupSeconds + cooldownSeconds + repeats * (work.durationSeconds + recovery.durationSeconds)
    }

}

struct IntervalWorkoutDraft: Equatable {
    var name: String
    var warmupMinutes: Int
    var repeats: Int
    var workLabel: String
    var workSeconds: Int
    var workIntensity: IntervalIntensity
    var recoveryLabel: String
    var recoverySeconds: Int
    var recoveryIntensity: IntervalIntensity
    var cooldownMinutes: Int

    init(
        name: String = "Run Intervals",
        warmupMinutes: Int = 10,
        repeats: Int = 6,
        workLabel: String = "Run",
        workSeconds: Int = 120,
        workIntensity: IntervalIntensity = .hard,
        recoveryLabel: String = "Recover",
        recoverySeconds: Int = 90,
        recoveryIntensity: IntervalIntensity = .easy,
        cooldownMinutes: Int = 5
    ) {
        self.name = name
        self.warmupMinutes = warmupMinutes
        self.repeats = repeats
        self.workLabel = workLabel
        self.workSeconds = workSeconds
        self.workIntensity = workIntensity
        self.recoveryLabel = recoveryLabel
        self.recoverySeconds = recoverySeconds
        self.recoveryIntensity = recoveryIntensity
        self.cooldownMinutes = cooldownMinutes
    }

    init(workout: IntervalWorkout) {
        self.init(
            name: workout.name,
            warmupMinutes: workout.warmupSeconds / 60,
            repeats: workout.repeats,
            workLabel: workout.work.label,
            workSeconds: workout.work.durationSeconds,
            workIntensity: workout.work.intensity,
            recoveryLabel: workout.recovery.label,
            recoverySeconds: workout.recovery.durationSeconds,
            recoveryIntensity: workout.recovery.intensity,
            cooldownMinutes: workout.cooldownSeconds / 60
        )
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedWorkLabel: String {
        normalizedLabel(workLabel, fallback: "Run")
    }

    var normalizedRecoveryLabel: String {
        normalizedLabel(recoveryLabel, fallback: "Recover")
    }

    var normalizedWarmupMinutes: Int {
        clamped(warmupMinutes, lower: 0, upper: 60)
    }

    var normalizedCooldownMinutes: Int {
        clamped(cooldownMinutes, lower: 0, upper: 60)
    }

    var normalizedRepeats: Int {
        clamped(repeats, lower: 1, upper: 30)
    }

    var normalizedWorkSeconds: Int {
        normalizedStepSeconds(workSeconds)
    }

    var normalizedRecoverySeconds: Int {
        normalizedStepSeconds(recoverySeconds)
    }

    var totalSeconds: Int {
        normalizedWarmupMinutes * 60 +
            normalizedCooldownMinutes * 60 +
            normalizedRepeats * (normalizedWorkSeconds + normalizedRecoverySeconds)
    }

    var canBuildWorkout: Bool {
        !normalizedName.isEmpty
    }

    func workout(
        id: UUID = UUID(),
        workID: UUID = UUID(),
        recoveryID: UUID = UUID()
    ) -> IntervalWorkout? {
        guard canBuildWorkout else { return nil }
        return IntervalWorkout(
            id: id,
            name: normalizedName,
            warmupSeconds: normalizedWarmupMinutes * 60,
            repeats: normalizedRepeats,
            work: IntervalStep(
                id: workID,
                label: normalizedWorkLabel,
                durationSeconds: normalizedWorkSeconds,
                intensity: workIntensity
            ),
            recovery: IntervalStep(
                id: recoveryID,
                label: normalizedRecoveryLabel,
                durationSeconds: normalizedRecoverySeconds,
                intensity: recoveryIntensity
            ),
            cooldownSeconds: normalizedCooldownMinutes * 60
        )
    }

    private func normalizedLabel(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedStepSeconds(_ seconds: Int) -> Int {
        let clampedSeconds = clamped(seconds, lower: 15, upper: 1_800)
        return Int((Double(clampedSeconds) / 15.0).rounded()) * 15
    }

    private func clamped(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}

struct IntervalStep: Codable, Hashable, Identifiable {
    var id: UUID
    var label: String
    var durationSeconds: Int
    var intensity: IntervalIntensity

    init(id: UUID = UUID(), label: String, durationSeconds: Int, intensity: IntervalIntensity) {
        self.id = id
        self.label = label
        self.durationSeconds = durationSeconds
        self.intensity = intensity
    }
}

enum IntervalIntensity: String, Codable, CaseIterable, Identifiable {
    case easy
    case steady
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .steady: return "Steady"
        case .hard: return "Hard"
        }
    }
}

struct WorkoutSummary: Codable, Identifiable, Hashable {
    var id: UUID
    var source: WorkoutDataSource
    var activity: WorkoutActivity
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distanceMeters: Double
    var activeEnergyKilocalories: Double
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var route: [RoutePoint]
    var heartRateSamples: [HeartRateSample]
    var stravaState: StravaUploadStatus

    init(
        id: UUID = UUID(),
        source: WorkoutDataSource = .healthKit,
        activity: WorkoutActivity,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        activeEnergyKilocalories: Double,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        route: [RoutePoint] = [],
        heartRateSamples: [HeartRateSample] = [],
        stravaState: StravaUploadStatus = .notUploaded
    ) {
        self.id = id
        self.source = source
        self.activity = activity
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.route = route
        self.heartRateSamples = heartRateSamples
        self.stravaState = stravaState
    }
}

enum WorkoutDataSource: String, Codable, Hashable {
    case healthKit
    case demo
}

struct DateRangeValue: Codable, Hashable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct ActivityEdit: Codable, Hashable, Identifiable {
    var id: UUID { workoutID }
    var workoutID: UUID
    var trimStartSeconds: TimeInterval
    var trimEndSeconds: TimeInterval
    var removedPauses: [DateRangeValue]

    init(
        workoutID: UUID,
        trimStartSeconds: TimeInterval = 0,
        trimEndSeconds: TimeInterval = 0,
        removedPauses: [DateRangeValue] = []
    ) {
        self.workoutID = workoutID
        self.trimStartSeconds = trimStartSeconds
        self.trimEndSeconds = trimEndSeconds
        self.removedPauses = removedPauses
    }

    var removedPauseSeconds: TimeInterval {
        removedPauses.reduce(0) { $0 + $1.duration }
    }

    var hasAdjustments: Bool {
        trimStartSeconds > 0 || trimEndSeconds > 0 || !removedPauses.isEmpty
    }

    func adjustedDuration(original: TimeInterval) -> TimeInterval {
        max(0, original - trimStartSeconds - trimEndSeconds - removedPauseSeconds)
    }
}

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double?
    var timestamp: Date
    var horizontalAccuracy: Double?
}

struct BestEffortResult: Identifiable, Hashable {
    var id: BestEffortDistance { distance }
    var distance: BestEffortDistance
    var workoutID: UUID
    var workoutStartDate: Date
    var duration: TimeInterval
    var segmentStart: Date
    var segmentEnd: Date
}

struct HeartRateSample: Codable, Hashable, Identifiable {
    var id: UUID
    var timestamp: Date
    var beatsPerMinute: Int

    init(id: UUID = UUID(), timestamp: Date, beatsPerMinute: Int) {
        self.id = id
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
    }
}

enum StravaUploadStatus: String, Codable, CaseIterable {
    case notUploaded
    case pending
    case uploading
    case processing
    case uploaded
    case failed

    var displayName: String {
        switch self {
        case .notUploaded: return "Not uploaded"
        case .pending: return "Pending"
        case .uploading: return "Uploading"
        case .processing: return "Processing"
        case .uploaded: return "Uploaded"
        case .failed: return "Failed"
        }
    }
}

enum WatchConnectivityPayloadKey {
    static let startActivity = "startActivity"
    static let settings = "settings"
    static let workoutFinished = "workoutFinished"
    static let completionID = "completionID"
    static let workoutID = "workoutID"
    static let activity = "activity"
    static let endedAt = "endedAt"
}

struct WatchWorkoutCompletion: Codable, Equatable, Identifiable {
    var id: UUID
    var workoutID: UUID
    var activity: WorkoutActivity?
    var endedAt: Date

    init(
        id: UUID = UUID(),
        workoutID: UUID,
        activity: WorkoutActivity?,
        endedAt: Date
    ) {
        self.id = id
        self.workoutID = workoutID
        self.activity = activity
        self.endedAt = endedAt
    }

    init?(payload: [String: Any]) {
        guard payload[WatchConnectivityPayloadKey.workoutFinished] as? Bool == true,
              let workoutIDValue = payload[WatchConnectivityPayloadKey.workoutID] as? String,
              let workoutID = UUID(uuidString: workoutIDValue),
              let endedAt = payload[WatchConnectivityPayloadKey.endedAt] as? Date else {
            return nil
        }

        let completionID = (payload[WatchConnectivityPayloadKey.completionID] as? String)
            .flatMap(UUID.init(uuidString:)) ?? workoutID
        let activity = (payload[WatchConnectivityPayloadKey.activity] as? String)
            .flatMap(WorkoutActivity.init(rawValue:))
        self.init(id: completionID, workoutID: workoutID, activity: activity, endedAt: endedAt)
    }

    var payload: [String: Any] {
        [
            WatchConnectivityPayloadKey.workoutFinished: true,
            WatchConnectivityPayloadKey.completionID: id.uuidString,
            WatchConnectivityPayloadKey.workoutID: workoutID.uuidString,
            WatchConnectivityPayloadKey.activity: activity?.rawValue ?? "",
            WatchConnectivityPayloadKey.endedAt: endedAt
        ]
    }
}

enum PendingWorkoutStartStore {
    private static let key = "pendingStartWorkoutActivity"

    static func set(_ activity: WorkoutActivity, defaults: UserDefaults = .standard) {
        defaults.set(activity.rawValue, forKey: key)
    }

    static func consume(defaults: UserDefaults = .standard) -> WorkoutActivity? {
        guard let raw = defaults.string(forKey: key),
              let activity = WorkoutActivity(rawValue: raw) else {
            return nil
        }
        defaults.removeObject(forKey: key)
        return activity
    }
}

struct StravaUploadRecord: Codable, Hashable, Identifiable {
    var id: UUID { workoutID }
    var workoutID: UUID
    var status: StravaUploadStatus
    var stravaUploadID: String?
    var stravaActivityID: String?
    var lastError: String?
    var updatedAt: Date

    init(
        workoutID: UUID,
        status: StravaUploadStatus,
        stravaUploadID: String? = nil,
        stravaActivityID: String? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.workoutID = workoutID
        self.status = status
        self.stravaUploadID = stravaUploadID
        self.stravaActivityID = stravaActivityID
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

struct WorkoutMetricSnapshot: Equatable {
    var elapsedSeconds: TimeInterval = 0
    var heartRate: Int?
    var distanceMeters: Double = 0
    var activeEnergyKilocalories: Double = 0
    var paceSecondsPerUnit: Double?
    var route: [RoutePoint] = []
    var headingDegrees: Double?

    static let empty = WorkoutMetricSnapshot()
}
