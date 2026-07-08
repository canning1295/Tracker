import Foundation

enum HeartRateZone: Int, CaseIterable, Identifiable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    var id: Int { rawValue }

    var displayName: String {
        "Zone \(rawValue)"
    }

    var colorName: String {
        switch self {
        case .zone1: return "blue"
        case .zone2: return "green"
        case .zone3: return "yellow"
        case .zone4: return "orange"
        case .zone5: return "red"
        }
    }
}

enum HeartRateZoneCalculator {
    static func zone(for heartRate: Int?, settings: HeartRateSettings) -> HeartRateZone? {
        guard let heartRate, settings.maxHeartRate > 0 else { return nil }
        let percent = Double(heartRate) / Double(settings.maxHeartRate)
        let bounds = normalizedZoneLowerBounds(settings.zoneBoundaries)
        if percent < bounds[1] { return .zone1 }
        if percent < bounds[2] { return .zone2 }
        if percent < bounds[3] { return .zone3 }
        if percent < bounds[4] { return .zone4 }
        return .zone5
    }

    static func bpmRangeText(for zone: HeartRateZone, settings: HeartRateSettings) -> String {
        guard settings.maxHeartRate > 0 else { return "--" }
        let bounds = normalizedZoneLowerBounds(settings.zoneBoundaries)
        let index = max(0, min(zone.rawValue - 1, bounds.count - 1))
        let lower = Int((bounds[index] * Double(settings.maxHeartRate)).rounded(.up))

        if zone == .zone1 {
            let upper = Int((bounds[1] * Double(settings.maxHeartRate)).rounded(.up)) - 1
            return "0-\(max(upper, 0)) bpm"
        }

        if zone == .zone5 {
            return "\(lower)+ bpm"
        }

        let upper = Int((bounds[index + 1] * Double(settings.maxHeartRate)).rounded(.up)) - 1
        return "\(lower)-\(max(lower, upper)) bpm"
    }

    static func zoneDurations(
        samples: [HeartRateSample],
        settings: HeartRateSettings,
        workoutEnd: Date? = nil,
        maximumSampleGap: TimeInterval = 30
    ) -> [HeartRateZone: TimeInterval] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [:] }

        var durations: [HeartRateZone: TimeInterval] = [:]
        for index in sorted.indices {
            let sample = sorted[index]
            let nextDate: Date
            if sorted.indices.contains(index + 1) {
                nextDate = sorted[index + 1].timestamp
            } else {
                nextDate = workoutEnd ?? sample.timestamp.addingTimeInterval(maximumSampleGap)
            }

            let seconds = min(maximumSampleGap, max(0, nextDate.timeIntervalSince(sample.timestamp)))
            guard seconds > 0, let zone = zone(for: sample.beatsPerMinute, settings: settings) else { continue }
            durations[zone, default: 0] += seconds
        }
        return durations
    }

    private static func normalizedZoneLowerBounds(_ configured: [Double]) -> [Double] {
        let defaults = [0.50, 0.60, 0.70, 0.80, 0.90]
        guard configured.count >= defaults.count else { return defaults }
        let values = Array(configured.prefix(defaults.count))
        guard values.allSatisfy({ $0 > 0 && $0 < 1 }) else { return defaults }
        guard zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else { return defaults }
        return values
    }
}

struct HeartRateDisplayPresentation: Equatable {
    var valueText: String
    var colorName: String

    init(valueText: String, colorName: String) {
        self.valueText = valueText
        self.colorName = colorName
    }

    init(heartRate: Int?, settings: HeartRateSettings) {
        valueText = heartRate.map(String.init) ?? "--"
        colorName = HeartRateZoneCalculator.zone(for: heartRate, settings: settings)?.colorName ?? "secondary"
    }
}

struct HeartRateSampleSummary: Equatable {
    var average: Int?
    var maximum: Int?
}

enum HeartRateSampleStatistics {
    static func summary(
        samples: [HeartRateSample],
        workoutEnd: Date? = nil,
        maximumSampleGap: TimeInterval = 30
    ) -> HeartRateSampleSummary {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            return HeartRateSampleSummary(average: nil, maximum: nil)
        }

        let maximum = sorted.map(\.beatsPerMinute).max()
        let cappedSampleGap = max(0, maximumSampleGap)
        var weightedTotal = 0.0
        var totalSeconds = 0.0

        for index in sorted.indices {
            let sample = sorted[index]
            let nextDate: Date
            if sorted.indices.contains(index + 1) {
                nextDate = sorted[index + 1].timestamp
            } else {
                nextDate = workoutEnd ?? sample.timestamp.addingTimeInterval(cappedSampleGap)
            }

            let seconds = min(cappedSampleGap, max(0, nextDate.timeIntervalSince(sample.timestamp)))
            guard seconds > 0 else { continue }
            weightedTotal += Double(sample.beatsPerMinute) * seconds
            totalSeconds += seconds
        }

        if totalSeconds > 0 {
            return HeartRateSampleSummary(
                average: Int((weightedTotal / totalSeconds).rounded()),
                maximum: maximum
            )
        }

        return HeartRateSampleSummary(
            average: arithmeticAverage(samples: sorted),
            maximum: maximum
        )
    }

    private static func arithmeticAverage(samples: [HeartRateSample]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0) { $0 + $1.beatsPerMinute }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}

enum PaceCalculator {
    static func paceSecondsPerUnit(distanceMeters: Double, elapsedSeconds: TimeInterval, unit: DistanceUnit) -> Double? {
        guard distanceMeters > 5, elapsedSeconds > 0 else { return nil }
        let units = distanceMeters / unit.metersPerUnit
        guard units > 0 else { return nil }
        return elapsedSeconds / units
    }

    static func rollingPace(points: [RoutePoint], windowSeconds: Int, unit: DistanceUnit) -> Double? {
        guard let last = points.last, points.count > 1 else { return nil }
        let cutoff = last.timestamp.addingTimeInterval(-TimeInterval(windowSeconds))
        let recent = points.filter { $0.timestamp >= cutoff }
        guard let first = recent.first, recent.count > 1 else { return nil }
        let meters = distanceMeters(between: first, and: last)
        let seconds = last.timestamp.timeIntervalSince(first.timestamp)
        return paceSecondsPerUnit(distanceMeters: meters, elapsedSeconds: seconds, unit: unit)
    }

    static func shouldRefreshDisplayedPace(
        elapsedSeconds: TimeInterval,
        lastRefreshElapsedSeconds: TimeInterval?,
        mode: PaceMode,
        rollingPaceSeconds: Int
    ) -> Bool {
        guard let lastRefreshElapsedSeconds else { return true }
        let refreshInterval: TimeInterval
        switch mode {
        case .rolling:
            refreshInterval = TimeInterval(max(5, rollingPaceSeconds))
        case .wholeWorkout, .currentSplit:
            refreshInterval = 5
        }
        return elapsedSeconds - lastRefreshElapsedSeconds >= refreshInterval
    }

    static func currentSplitPace(points: [RoutePoint], unit: DistanceUnit) -> Double? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }

        let totalDistance = totalDistanceMeters(points: points)
        let splitStartDistance = floor(totalDistance / unit.metersPerUnit) * unit.metersPerUnit
        let splitDistance = totalDistance - splitStartDistance
        guard splitDistance > 5 else { return nil }

        var cumulativeDistance = 0.0
        var splitStartPoint = first

        if splitStartDistance > 0 {
            for pair in zip(points, points.dropFirst()) {
                let segmentDistance = distanceMeters(between: pair.0, and: pair.1)
                let nextDistance = cumulativeDistance + segmentDistance

                if nextDistance >= splitStartDistance {
                    let segmentProgress = segmentDistance > 0 ? (splitStartDistance - cumulativeDistance) / segmentDistance : 0
                    splitStartPoint = interpolatedPoint(from: pair.0, to: pair.1, progress: min(max(segmentProgress, 0), 1))
                    break
                }

                cumulativeDistance = nextDistance
            }
        }

        return paceSecondsPerUnit(
            distanceMeters: splitDistance,
            elapsedSeconds: last.timestamp.timeIntervalSince(splitStartPoint.timestamp),
            unit: unit
        )
    }

    static func distanceMeters(between first: RoutePoint, and second: RoutePoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = first.latitude * .pi / 180
        let lat2 = second.latitude * .pi / 180
        let deltaLat = (second.latitude - first.latitude) * .pi / 180
        let deltaLon = (second.longitude - first.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    static func totalDistanceMeters(points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + distanceMeters(between: pair.0, and: pair.1)
        }
    }

    private static func interpolatedPoint(from start: RoutePoint, to end: RoutePoint, progress: Double) -> RoutePoint {
        RoutePoint(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress,
            altitudeMeters: interpolatedAltitude(from: start, to: end, progress: progress),
            timestamp: start.timestamp.addingTimeInterval(end.timestamp.timeIntervalSince(start.timestamp) * progress),
            horizontalAccuracy: start.horizontalAccuracy
        )
    }

    private static func interpolatedAltitude(from start: RoutePoint, to end: RoutePoint, progress: Double) -> Double? {
        guard let startAltitude = start.altitudeMeters, let endAltitude = end.altitudeMeters else { return nil }
        return startAltitude + (endAltitude - startAltitude) * progress
    }
}

enum WorkoutCalories {
    static func activeKilocalories(fromHealthKitActiveKilocalories kilocalories: Double) -> Double {
        max(0, kilocalories)
    }

    static func activeKilocalories(fromGrossKilocalorieEstimate kilocalories: Double, duration: TimeInterval, userMetrics: UserMetrics) -> Double {
        max(0, kilocalories - estimatedBasalKilocalories(duration: duration, userMetrics: userMetrics))
    }

    static func estimatedBasalKilocalories(duration: TimeInterval, userMetrics: UserMetrics) -> Double {
        guard duration > 0 else { return 0 }

        if let dailyBMR = estimatedDailyBasalKilocalories(userMetrics: userMetrics) {
            return dailyBMR * duration / 86_400
        }

        guard let weightKilograms = userMetrics.weightKilograms, weightKilograms > 0 else { return 0 }
        return weightKilograms * duration / 3_600
    }

    private static func estimatedDailyBasalKilocalories(userMetrics: UserMetrics) -> Double? {
        guard
            let weightKilograms = userMetrics.weightKilograms, weightKilograms > 0,
            let heightCentimeters = userMetrics.heightCentimeters, heightCentimeters > 0,
            let age = userMetrics.age, age > 0
        else {
            return nil
        }

        let base = 10 * weightKilograms + 6.25 * heightCentimeters - 5 * Double(age)
        switch userMetrics.biologicalSex {
        case .male:
            return base + 5
        case .female:
            return base - 161
        case .other, .notSet, nil:
            return base - 78
        }
    }
}

enum WorkoutFormatter {
    static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        let value = meters / unit.metersPerUnit
        return String(format: "%.2f %@", value, unit.shortName)
    }

    static func pace(_ secondsPerUnit: Double?, unit: DistanceUnit) -> String {
        guard let secondsPerUnit, secondsPerUnit.isFinite, secondsPerUnit > 0 else { return "--" }
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d/%@", minutes, seconds, unit.shortName)
    }

    static func activeCalories(_ value: Double) -> String {
        "\(Int(WorkoutCalories.activeKilocalories(fromHealthKitActiveKilocalories: value).rounded())) cal"
    }
}

struct SplitSummary: Equatable {
    var distanceMeters: Double
    var paceSecondsPerUnit: Double?
}

enum SplitBuilder {
    static func splits(for workout: WorkoutSummary, unit: DistanceUnit) -> [SplitSummary] {
        guard workout.activity.recordsDistance else { return [] }
        if workout.route.count > 1 {
            let routeSplits = routeBasedSplits(points: workout.route, unit: unit)
            if !routeSplits.isEmpty {
                return routeSplits
            }
        }
        guard workout.distanceMeters > 0 else { return [] }
        return proportionalSplits(for: workout, unit: unit)
    }

    private static func routeBasedSplits(points: [RoutePoint], unit: DistanceUnit) -> [SplitSummary] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else { return [] }

        let splitDistance = unit.metersPerUnit
        var splits: [SplitSummary] = []
        var splitStartPoint = first
        var splitStartDistance = 0.0
        var nextBoundaryDistance = splitDistance
        var cumulativeDistance = 0.0

        for pair in zip(sorted, sorted.dropFirst()) {
            let segmentDistance = PaceCalculator.distanceMeters(between: pair.0, and: pair.1)
            guard segmentDistance > 0 else { continue }

            let nextCumulativeDistance = cumulativeDistance + segmentDistance

            while nextBoundaryDistance <= nextCumulativeDistance {
                let progress = (nextBoundaryDistance - cumulativeDistance) / segmentDistance
                let boundaryPoint = interpolatedPoint(from: pair.0, to: pair.1, progress: min(max(progress, 0), 1))
                let distance = nextBoundaryDistance - splitStartDistance
                let duration = boundaryPoint.timestamp.timeIntervalSince(splitStartPoint.timestamp)
                splits.append(SplitSummary(
                    distanceMeters: distance,
                    paceSecondsPerUnit: PaceCalculator.paceSecondsPerUnit(distanceMeters: distance, elapsedSeconds: duration, unit: unit)
                ))
                splitStartPoint = boundaryPoint
                splitStartDistance = nextBoundaryDistance
                nextBoundaryDistance += splitDistance
            }

            cumulativeDistance = nextCumulativeDistance
        }

        let finalDistance = cumulativeDistance - splitStartDistance
        let finalDuration = last.timestamp.timeIntervalSince(splitStartPoint.timestamp)
        if finalDistance > 5, finalDuration > 0 {
            splits.append(SplitSummary(
                distanceMeters: finalDistance,
                paceSecondsPerUnit: PaceCalculator.paceSecondsPerUnit(distanceMeters: finalDistance, elapsedSeconds: finalDuration, unit: unit)
            ))
        }

        return splits
    }

    private static func proportionalSplits(for workout: WorkoutSummary, unit: DistanceUnit) -> [SplitSummary] {
        let splitDistance = unit.metersPerUnit
        var splits: [SplitSummary] = []
        var remainingDistance = workout.distanceMeters

        while remainingDistance > 0 {
            let distance = min(splitDistance, remainingDistance)
            let duration = workout.distanceMeters > 0 ? workout.duration * (distance / workout.distanceMeters) : 0
            splits.append(SplitSummary(
                distanceMeters: distance,
                paceSecondsPerUnit: PaceCalculator.paceSecondsPerUnit(distanceMeters: distance, elapsedSeconds: duration, unit: unit)
            ))
            remainingDistance -= distance
        }
        return splits
    }

    private static func interpolatedPoint(from start: RoutePoint, to end: RoutePoint, progress: Double) -> RoutePoint {
        RoutePoint(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress,
            altitudeMeters: interpolatedAltitude(from: start, to: end, progress: progress),
            timestamp: start.timestamp.addingTimeInterval(end.timestamp.timeIntervalSince(start.timestamp) * progress),
            horizontalAccuracy: start.horizontalAccuracy
        )
    }

    private static func interpolatedAltitude(from start: RoutePoint, to end: RoutePoint, progress: Double) -> Double? {
        guard let startAltitude = start.altitudeMeters, let endAltitude = end.altitudeMeters else { return nil }
        return startAltitude + (endAltitude - startAltitude) * progress
    }
}

struct IntervalProgress: Equatable {
    var title: String
    var detail: String
    var intensity: IntervalIntensity?
    var stepIndex: Int
    var stepCount: Int
    var elapsedInStep: TimeInterval
    var remainingInStep: TimeInterval
    var fractionComplete: Double
    var isComplete: Bool
}

enum IntervalTimeline {
    static func progress(for workout: IntervalWorkout, elapsedSeconds: TimeInterval) -> IntervalProgress {
        let segments = segments(for: workout)
        guard !segments.isEmpty else {
            return IntervalProgress(
                title: "Workout",
                detail: "Complete",
                intensity: nil,
                stepIndex: 0,
                stepCount: 0,
                elapsedInStep: 0,
                remainingInStep: 0,
                fractionComplete: 1,
                isComplete: true
            )
        }

        var remaining = max(0, elapsedSeconds)
        for (index, segment) in segments.enumerated() {
            if remaining < segment.duration {
                let elapsed = remaining
                return IntervalProgress(
                    title: segment.title,
                    detail: segment.detail,
                    intensity: segment.intensity,
                    stepIndex: index + 1,
                    stepCount: segments.count,
                    elapsedInStep: elapsed,
                    remainingInStep: max(0, segment.duration - elapsed),
                    fractionComplete: segment.duration > 0 ? min(1, elapsed / segment.duration) : 1,
                    isComplete: false
                )
            }
            remaining -= segment.duration
        }

        return IntervalProgress(
            title: "Complete",
            detail: "End when ready",
            intensity: nil,
            stepIndex: segments.count,
            stepCount: segments.count,
            elapsedInStep: 0,
            remainingInStep: 0,
            fractionComplete: 1,
            isComplete: true
        )
    }

    private static func segments(for workout: IntervalWorkout) -> [IntervalSegment] {
        var segments: [IntervalSegment] = []

        if workout.warmupSeconds > 0 {
            segments.append(IntervalSegment(title: "Warm Up", detail: "Step 1", duration: TimeInterval(workout.warmupSeconds), intensity: .easy))
        }

        let repeats = max(0, workout.repeats)
        if repeats > 0 {
            for repeatIndex in 1...repeats {
                segments.append(IntervalSegment(title: workout.work.label, detail: "Rep \(repeatIndex) of \(repeats)", duration: TimeInterval(workout.work.durationSeconds), intensity: workout.work.intensity))
                segments.append(IntervalSegment(title: workout.recovery.label, detail: "Rep \(repeatIndex) of \(repeats)", duration: TimeInterval(workout.recovery.durationSeconds), intensity: workout.recovery.intensity))
            }
        }

        if workout.cooldownSeconds > 0 {
            segments.append(IntervalSegment(title: "Cool Down", detail: "Final step", duration: TimeInterval(workout.cooldownSeconds), intensity: .easy))
        }

        return segments.filter { $0.duration > 0 }
    }
}

private struct IntervalSegment {
    var title: String
    var detail: String
    var duration: TimeInterval
    var intensity: IntervalIntensity?
}

struct WeeklySummary: Equatable {
    var weekStart: Date
    var totalTime: TimeInterval
    var totalDistanceMeters: Double
    var activeCalories: Double
    var workoutCount: Int
    var activeDays: Int
    var averageHeartRate: Int?
    var timeByActivity: [WorkoutActivity: TimeInterval]
    var distanceByActivity: [WorkoutActivity: Double]
    var heartRateZoneDurations: [HeartRateZone: TimeInterval]
}

enum SummaryEngine {
    static func summary(
        workouts: [WorkoutSummary],
        heartRateSettings: HeartRateSettings,
        interval: DateInterval,
        calendar: Calendar = .current
    ) -> WeeklySummary {
        let included = workouts.filter { $0.startDate >= interval.start && $0.startDate < interval.end }
        let zoneDurations = included.reduce(into: [HeartRateZone: TimeInterval]()) { partial, workout in
            let workoutZones = HeartRateZoneCalculator.zoneDurations(
                samples: workout.heartRateSamples,
                settings: heartRateSettings,
                workoutEnd: workout.endDate
            )
            for (zone, duration) in workoutZones {
                partial[zone, default: 0] += duration
            }
        }
        let activeDays = Set(included.map { calendar.startOfDay(for: $0.startDate) }).count
        return WeeklySummary(
            weekStart: interval.start,
            totalTime: included.reduce(0) { $0 + $1.duration },
            totalDistanceMeters: included.reduce(0) { $0 + $1.distanceMeters },
            activeCalories: included.reduce(0) { $0 + $1.activeEnergyKilocalories },
            workoutCount: included.count,
            activeDays: activeDays,
            averageHeartRate: averageHeartRate(for: included),
            timeByActivity: Dictionary(grouping: included, by: \.activity).mapValues { $0.reduce(0) { $0 + $1.duration } },
            distanceByActivity: Dictionary(grouping: included, by: \.activity).mapValues { $0.reduce(0) { $0 + $1.distanceMeters } },
            heartRateZoneDurations: zoneDurations
        )
    }

    static func currentWeekSummary(
        workouts: [WorkoutSummary],
        heartRateSettings: HeartRateSettings,
        calendar: Calendar = .current
    ) -> WeeklySummary {
        let now = Date()
        let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 3600)
        return summary(workouts: workouts, heartRateSettings: heartRateSettings, interval: interval, calendar: calendar)
    }

    static func recentWeeklySummaries(
        workouts: [WorkoutSummary],
        heartRateSettings: HeartRateSettings,
        weekCount: Int = 4,
        calendar: Calendar = .current
    ) -> [WeeklySummary] {
        let now = Date()
        let currentInterval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 3600)
        return (0..<max(weekCount, 1)).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentInterval.start) else { return nil }
            let interval = DateInterval(start: weekStart, duration: currentInterval.duration)
            return summary(workouts: workouts, heartRateSettings: heartRateSettings, interval: interval, calendar: calendar)
        }
    }

    private static func averageHeartRate(for workouts: [WorkoutSummary]) -> Int? {
        let weighted = workouts.compactMap { workout -> (heartRate: Int, duration: TimeInterval)? in
            guard let heartRate = representativeHeartRate(for: workout), workout.duration > 0 else { return nil }
            return (heartRate, workout.duration)
        }
        let totalDuration = weighted.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0 else { return nil }
        let weightedTotal = weighted.reduce(0) { $0 + Double($1.heartRate) * $1.duration }
        return Int((weightedTotal / totalDuration).rounded())
    }

    private static func representativeHeartRate(for workout: WorkoutSummary) -> Int? {
        if let averageHeartRate = workout.averageHeartRate {
            return averageHeartRate
        }

        return HeartRateSampleStatistics.summary(
            samples: workout.heartRateSamples,
            workoutEnd: workout.endDate
        ).average
    }
}

enum PauseDetector {
    static func candidatePauseRanges(route: [RoutePoint], minimumDuration: TimeInterval = 30, radiusMeters: Double = 20) -> [ClosedRange<Date>] {
        guard route.count > 2 else { return [] }
        var ranges: [ClosedRange<Date>] = []
        var clusterStart: RoutePoint?
        var clusterPoints: [RoutePoint] = []

        for point in route {
            if clusterStart == nil {
                clusterStart = point
                clusterPoints = [point]
                continue
            }

            guard let start = clusterStart else { continue }
            let distance = PaceCalculator.distanceMeters(between: start, and: point)
            if distance <= radiusMeters {
                clusterPoints.append(point)
            } else {
                if let first = clusterPoints.first, let last = clusterPoints.last, last.timestamp.timeIntervalSince(first.timestamp) >= minimumDuration {
                    ranges.append(first.timestamp...last.timestamp)
                }
                clusterStart = point
                clusterPoints = [point]
            }
        }

        if let first = clusterPoints.first, let last = clusterPoints.last, last.timestamp.timeIntervalSince(first.timestamp) >= minimumDuration {
            ranges.append(first.timestamp...last.timestamp)
        }
        return ranges
    }
}

enum WorkoutEditApplier {
    static func adjustedWorkout(_ workout: WorkoutSummary, edit: ActivityEdit) -> WorkoutSummary {
        guard edit.hasAdjustments else { return workout }

        let keptStart = workout.startDate.addingTimeInterval(clampedTrimStart(for: workout, edit: edit))
        let keptEndBeforePauses = workout.endDate.addingTimeInterval(-clampedTrimEnd(for: workout, edit: edit, keptStart: keptStart))
        guard keptEndBeforePauses > keptStart else {
            return WorkoutSummary(
                id: workout.id,
                source: workout.source,
                activity: workout.activity,
                startDate: keptStart,
                endDate: keptStart,
                duration: 0,
                distanceMeters: 0,
                activeEnergyKilocalories: 0,
                averageHeartRate: nil,
                maxHeartRate: nil,
                route: [],
                heartRateSamples: [],
                stravaState: workout.stravaState
            )
        }

        let pauseRanges = normalizedPauseRanges(edit.removedPauses, start: keptStart, end: keptEndBeforePauses)
        let removedSeconds = pauseRanges.reduce(0) { $0 + $1.duration }
        let adjustedEnd = keptEndBeforePauses.addingTimeInterval(-removedSeconds)
        let adjustedRoute = adjustedRoutePoints(workout.route, start: keptStart, end: keptEndBeforePauses, pauseRanges: pauseRanges)
        let adjustedHeartRates = adjustedHeartRateSamples(workout.heartRateSamples, start: keptStart, end: keptEndBeforePauses, pauseRanges: pauseRanges)
        let adjustedDuration = max(0, adjustedEnd.timeIntervalSince(keptStart))
        let durationRatio = workout.duration > 0 ? min(max(adjustedDuration / workout.duration, 0), 1) : 0
        let adjustedDistance: Double
        if workout.activity.recordsDistance {
            adjustedDistance = adjustedRoute.count > 1
                ? PaceCalculator.totalDistanceMeters(points: adjustedRoute)
                : workout.distanceMeters * durationRatio
        } else {
            adjustedDistance = 0
        }
        let adjustedHeartRateSummary = HeartRateSampleStatistics.summary(samples: adjustedHeartRates, workoutEnd: adjustedEnd)
        let adjustedAverageHeartRate = adjustedHeartRateSummary.average
            ?? (workout.heartRateSamples.isEmpty ? workout.averageHeartRate : nil)
        let adjustedMaxHeartRate = adjustedHeartRateSummary.maximum
            ?? (workout.heartRateSamples.isEmpty ? workout.maxHeartRate : nil)

        return WorkoutSummary(
            id: workout.id,
            source: workout.source,
            activity: workout.activity,
            startDate: keptStart,
            endDate: adjustedEnd,
            duration: adjustedDuration,
            distanceMeters: adjustedDistance,
            activeEnergyKilocalories: workout.activeEnergyKilocalories * durationRatio,
            averageHeartRate: adjustedAverageHeartRate,
            maxHeartRate: adjustedMaxHeartRate,
            route: adjustedRoute,
            heartRateSamples: adjustedHeartRates,
            stravaState: workout.stravaState
        )
    }

    static func removedPauseSeconds(for workout: WorkoutSummary, edit: ActivityEdit) -> TimeInterval {
        guard edit.hasAdjustments else { return 0 }
        let keptStart = workout.startDate.addingTimeInterval(clampedTrimStart(for: workout, edit: edit))
        let keptEnd = workout.endDate.addingTimeInterval(-clampedTrimEnd(for: workout, edit: edit, keptStart: keptStart))
        guard keptEnd > keptStart else { return 0 }
        return normalizedPauseRanges(edit.removedPauses, start: keptStart, end: keptEnd).reduce(0) { $0 + $1.duration }
    }

    private static func clampedTrimStart(for workout: WorkoutSummary, edit: ActivityEdit) -> TimeInterval {
        min(max(edit.trimStartSeconds, 0), max(workout.duration, 0))
    }

    private static func clampedTrimEnd(for workout: WorkoutSummary, edit: ActivityEdit, keptStart: Date) -> TimeInterval {
        min(max(edit.trimEndSeconds, 0), max(0, workout.endDate.timeIntervalSince(keptStart)))
    }

    private static func normalizedPauseRanges(_ ranges: [DateRangeValue], start: Date, end: Date) -> [DateRangeValue] {
        let clamped = ranges
            .map { DateRangeValue(start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        var merged: [DateRangeValue] = []
        for range in clamped {
            guard var last = merged.last else {
                merged.append(range)
                continue
            }

            if range.start <= last.end {
                last.end = max(last.end, range.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func adjustedRoutePoints(_ points: [RoutePoint], start: Date, end: Date, pauseRanges: [DateRangeValue]) -> [RoutePoint] {
        points
            .sorted { $0.timestamp < $1.timestamp }
            .filter { isKeptTimestamp($0.timestamp, start: start, end: end, pauseRanges: pauseRanges) }
            .map { point in
                RoutePoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitudeMeters: point.altitudeMeters,
                    timestamp: adjustedTimestamp(point.timestamp, pauseRanges: pauseRanges),
                    horizontalAccuracy: point.horizontalAccuracy
                )
            }
    }

    private static func adjustedHeartRateSamples(_ samples: [HeartRateSample], start: Date, end: Date, pauseRanges: [DateRangeValue]) -> [HeartRateSample] {
        samples
            .sorted { $0.timestamp < $1.timestamp }
            .filter { isKeptTimestamp($0.timestamp, start: start, end: end, pauseRanges: pauseRanges) }
            .map { sample in
                HeartRateSample(
                    id: sample.id,
                    timestamp: adjustedTimestamp(sample.timestamp, pauseRanges: pauseRanges),
                    beatsPerMinute: sample.beatsPerMinute
                )
            }
    }

    private static func isKeptTimestamp(_ timestamp: Date, start: Date, end: Date, pauseRanges: [DateRangeValue]) -> Bool {
        guard timestamp >= start, timestamp <= end else { return false }
        return !pauseRanges.contains { timestamp >= $0.start && timestamp <= $0.end }
    }

    private static func adjustedTimestamp(_ timestamp: Date, pauseRanges: [DateRangeValue]) -> Date {
        let shift = pauseRanges.reduce(0) { total, range in
            guard timestamp > range.start else { return total }
            return total + max(0, min(timestamp, range.end).timeIntervalSince(range.start))
        }
        return timestamp.addingTimeInterval(-shift)
    }
}

enum VO2MaxEstimator {
    struct HistoryPoint: Identifiable, Equatable {
        var id: UUID { workoutID }
        var workoutID: UUID
        var date: Date
        var activity: WorkoutActivity
        var estimate: Double
    }

    struct HistorySummary: Equatable {
        var points: [HistoryPoint]
        var current: Double
        var recentAverage: Double
        var best: Double
        var changeFromPrevious: Double?
    }

    static func estimate(
        workout: WorkoutSummary,
        userMetrics: UserMetrics,
        settings: HeartRateSettings
    ) -> Double? {
        guard workout.activity == .outdoorRun || workout.activity == .outdoorWalk else { return nil }
        guard workout.distanceMeters >= 1000, workout.duration > 0 else { return nil }
        guard let averageHeartRate = workout.averageHeartRate, averageHeartRate > 0 else { return nil }

        let speedMetersPerMinute = workout.distanceMeters / (workout.duration / 60)
        let effort = effortFraction(averageHeartRate: averageHeartRate, userMetrics: userMetrics, settings: settings)
        guard effort > 0.30 else { return nil }

        // ACSM-style oxygen cost estimate for level running/walking, scaled by effort.
        let baseOxygenCost = workout.activity == .outdoorRun
            ? 0.2 * speedMetersPerMinute + 3.5
            : 0.1 * speedMetersPerMinute + 3.5
        var estimate = baseOxygenCost / effort

        if let age = userMetrics.age {
            estimate -= max(0, Double(age - 35)) * 0.05
        }
        estimate += bodyMetricAdjustment(userMetrics)
        estimate = calibratedEstimate(estimate, effort: effort, knownVO2Max: userMetrics.knownVO2Max)
        return max(15, min(estimate, 85))
    }

    static func history(
        workouts: [WorkoutSummary],
        userMetrics: UserMetrics,
        settings: HeartRateSettings,
        recentSampleCount: Int = 5
    ) -> HistorySummary? {
        let points = workouts
            .sorted { $0.startDate > $1.startDate }
            .compactMap { workout -> HistoryPoint? in
                guard let estimate = estimate(workout: workout, userMetrics: userMetrics, settings: settings) else {
                    return nil
                }
                return HistoryPoint(
                    workoutID: workout.id,
                    date: workout.startDate,
                    activity: workout.activity,
                    estimate: estimate
                )
            }

        guard let current = points.first else { return nil }
        let recentPoints = Array(points.prefix(max(recentSampleCount, 1)))
        let recentAverage = recentPoints.reduce(0) { $0 + $1.estimate } / Double(recentPoints.count)
        let best = points.map(\.estimate).max() ?? current.estimate
        let previous = points.dropFirst().first?.estimate

        return HistorySummary(
            points: points,
            current: current.estimate,
            recentAverage: recentAverage,
            best: best,
            changeFromPrevious: previous.map { current.estimate - $0 }
        )
    }

    private static func effortFraction(
        averageHeartRate: Int,
        userMetrics: UserMetrics,
        settings: HeartRateSettings
    ) -> Double {
        let maxHeartRate = Double(max(settings.maxHeartRate, 1))
        let averageHeartRate = Double(averageHeartRate)
        let maxHeartRateFraction = averageHeartRate / maxHeartRate

        if let restingHeartRate = userMetrics.restingHeartRate {
            let resting = Double(restingHeartRate)
            if resting > 20, maxHeartRate > resting, averageHeartRate > resting {
                let reserveFraction = (averageHeartRate - resting) / (maxHeartRate - resting)
                return (maxHeartRateFraction + reserveFraction) / 2
            }
        }

        return maxHeartRateFraction
    }

    private static func bodyMetricAdjustment(_ userMetrics: UserMetrics) -> Double {
        var adjustment = 0.0

        if let height = userMetrics.heightCentimeters,
           let weight = userMetrics.weightKilograms,
           height > 0,
           weight > 0 {
            let heightMeters = height / 100
            let bmi = weight / (heightMeters * heightMeters)
            adjustment -= max(0, bmi - 24) * 0.20
            adjustment += max(0, min(22 - bmi, 4)) * 0.10
        }

        if let restingHeartRate = userMetrics.restingHeartRate {
            adjustment += min(4, max(-4, (60 - Double(restingHeartRate)) * 0.12))
        }

        switch userMetrics.biologicalSex {
        case .male:
            adjustment += 0.5
        case .female:
            adjustment -= 0.5
        case .other, .notSet, nil:
            break
        }

        return adjustment
    }

    private static func calibratedEstimate(_ estimate: Double, effort: Double, knownVO2Max: Double?) -> Double {
        guard let knownVO2Max, knownVO2Max > 0 else { return estimate }
        if effort < 0.75, estimate < knownVO2Max * 0.70 {
            return knownVO2Max
        }
        return knownVO2Max + (estimate - knownVO2Max) * 0.40
    }
}
