import Foundation
import CoreLocation
import HealthKit

final class HealthKitClient {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitClientError.healthDataUnavailable
        }

        var readTypes = Set<HKObjectType>()
        var shareTypes = Set<HKSampleType>()

        readTypes.insert(HKObjectType.workoutType())
        shareTypes.insert(HKObjectType.workoutType())

        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
            shareTypes.insert(activeEnergy)
        }
        if let walkingRunning = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            readTypes.insert(walkingRunning)
            shareTypes.insert(walkingRunning)
        }
        if let cycling = HKObjectType.quantityType(forIdentifier: .distanceCycling) {
            readTypes.insert(cycling)
            shareTypes.insert(cycling)
        }
        if let vo2 = HKObjectType.quantityType(forIdentifier: .vo2Max) {
            readTypes.insert(vo2)
        }
        if let height = HKObjectType.quantityType(forIdentifier: .height) {
            readTypes.insert(height)
        }
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            readTypes.insert(bodyMass)
        }
        if let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            readTypes.insert(restingHeartRate)
        }
        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            readTypes.insert(biologicalSex)
        }
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(dateOfBirth)
        }
        readTypes.insert(HKSeriesType.workoutRoute())
        shareTypes.insert(HKSeriesType.workoutRoute())

        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func loadUserMetrics() async throws -> UserMetrics {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitClientError.healthDataUnavailable
        }

        async let height = latestQuantityValue(identifier: .height, unit: .meter())
        async let bodyMass = latestQuantityValue(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let restingHeartRate = latestQuantityValue(identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let vo2Max = latestQuantityValue(identifier: .vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute()))

        let heightMeters = try await height
        let weightKilograms = try await bodyMass
        let restingBPM = try await restingHeartRate
        let knownVO2Max = try await vo2Max

        return UserMetrics(
            age: ageFromHealth(),
            biologicalSex: biologicalSexFromHealth(),
            heightCentimeters: heightMeters.map { $0 * 100 },
            weightKilograms: weightKilograms,
            restingHeartRate: restingBPM.map { Int($0.rounded()) },
            knownVO2Max: knownVO2Max
        )
    }

    func deleteWorkout(id: UUID) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitClientError.healthDataUnavailable
        }

        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForObject(with: id)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        guard let workout = workouts.first else {
            throw HealthKitClientError.workoutNotFound
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(workout) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitClientError.deleteFailed)
                }
            }
        }
    }

    func loadRecentWorkouts(limit: Int) async throws -> [WorkoutSummary] {
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: nil, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            self.store.execute(query)
        }

        var summaries: [WorkoutSummary] = []
        for workout in workouts {
            guard let activity = WorkoutActivity.fromHealthKit(activityType: workout.workoutActivityType, isIndoor: workout.isIndoorWorkout) else {
                continue
            }
            let samples = (try? await heartRateSamples(for: workout)) ?? []
            let heartRate = HeartRateSampleStatistics.summary(samples: samples, workoutEnd: workout.endDate)
            let route = activity.environment == .outdoor ? ((try? await routePoints(for: workout)) ?? []) : []
            summaries.append(
                WorkoutSummary(
                    id: UUID(uuidString: workout.uuid.uuidString) ?? UUID(),
                    source: .healthKit,
                    activity: activity,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    duration: workout.duration,
                    distanceMeters: distanceMeters(for: workout, activity: activity),
                    activeEnergyKilocalories: activeEnergyKilocalories(for: workout),
                    averageHeartRate: heartRate.average,
                    maxHeartRate: heartRate.maximum,
                    route: route,
                    heartRateSamples: samples,
                    stravaState: .notUploaded
                )
            )
        }
        return summaries
    }

    private func heartRateSamples(for workout: HKWorkout) async throws -> [HeartRateSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let associatedPredicate = HKQuery.predicateForObjects(from: workout)
        let associatedSamples = try await heartRateSamples(type: heartRateType, predicate: associatedPredicate)
        if !associatedSamples.isEmpty {
            return associatedSamples
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: [.strictStartDate, .strictEndDate]
        )
        return try await heartRateSamples(type: heartRateType, predicate: datePredicate)
    }

    private func heartRateSamples(type heartRateType: HKQuantityType, predicate: NSPredicate) async throws -> [HeartRateSample] {
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let heartRates = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateSample(
                        timestamp: $0.startDate,
                        beatsPerMinute: Int($0.quantity.doubleValue(for: unit).rounded())
                    )
                }
                continuation.resume(returning: heartRates)
            }
            store.execute(query)
        }
    }

    private func routePoints(for workout: HKWorkout) async throws -> [RoutePoint] {
        let routes = try await workoutRoutes(for: workout)
        var points: [RoutePoint] = []

        for route in routes {
            let locations = try await locations(for: route)
            points.append(contentsOf: locations.map {
                RoutePoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    altitudeMeters: $0.altitude,
                    timestamp: $0.timestamp,
                    horizontalAccuracy: $0.horizontalAccuracy
                )
            })
        }

        return points.sorted { $0.timestamp < $1.timestamp }
    }

    private func workoutRoutes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var locations: [CLLocation] = []
            var didResume = false
            let query = HKWorkoutRouteQuery(route: route) { _, newLocations, done, error in
                if didResume { return }
                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                if let newLocations {
                    locations.append(contentsOf: newLocations)
                }
                if done {
                    didResume = true
                    continuation.resume(returning: locations)
                }
            }
            store.execute(query)
        }
    }

    private func activeEnergyKilocalories(for workout: HKWorkout) -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }

    private func distanceMeters(for workout: HKWorkout, activity: WorkoutActivity) -> Double {
        guard activity.recordsDistance else { return 0 }
        let identifier: HKQuantityTypeIdentifier = activity == .outdoorBike || activity == .indoorBike ? .distanceCycling : .distanceWalkingRunning
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
    }

    private func latestQuantityValue(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func ageFromHealth(calendar: Calendar = .current) -> Int? {
        guard let birthDate = try? store.dateOfBirthComponents().date else { return nil }
        let components = calendar.dateComponents([.year], from: birthDate, to: Date())
        return components.year
    }

    private func biologicalSexFromHealth() -> BiologicalSex? {
        guard let sex = try? store.biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female:
            return .female
        case .male:
            return .male
        case .other:
            return .other
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }
}

enum HealthKitClientError: LocalizedError {
    case healthDataUnavailable
    case workoutNotFound
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .workoutNotFound:
            return "That workout was not found in Apple Health."
        case .deleteFailed:
            return "Apple Health did not delete the workout."
        }
    }
}

private extension HKWorkout {
    var isIndoorWorkout: Bool {
        metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
    }
}
