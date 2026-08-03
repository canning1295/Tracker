import XCTest

#if canImport(HealthKit)
import HealthKit
#endif

final class WorkoutCoreTests: XCTestCase {
    func testCrownMenuScrollDownMovesSelectionDown() {
        let model = CrownMenuScrollModel(optionCount: 3, hasBack: false, hasForward: true)

        XCTAssertEqual(model.crownValue(forSelection: 0), 0)
        XCTAssertEqual(model.action(forCrownValue: -1, currentSelectionIndex: 0), .select(1))
        XCTAssertEqual(model.action(forCrownValue: -2, currentSelectionIndex: 1), .select(2))
        XCTAssertEqual(model.action(forCrownValue: 0, currentSelectionIndex: 0), nil)
    }

    func testCrownMenuScrollUpBacksOnlyFromTopSelection() {
        let model = CrownMenuScrollModel(optionCount: 3, hasBack: true, hasForward: true)

        XCTAssertEqual(model.crownLowerBound, -3)
        XCTAssertEqual(model.crownUpperBound, 1)
        XCTAssertEqual(model.action(forCrownValue: 1, currentSelectionIndex: 1), .select(0))
        XCTAssertEqual(model.action(forCrownValue: 1, currentSelectionIndex: 0), .back)
    }

    func testCrownMenuForwardRequiresCurrentBottomSelection() {
        let model = CrownMenuScrollModel(optionCount: 3, hasBack: false, hasForward: true)

        XCTAssertEqual(model.action(forCrownValue: -3, currentSelectionIndex: 1), .select(2))
        XCTAssertEqual(model.action(forCrownValue: -3, currentSelectionIndex: 2), .forward(2))
    }

    func testCrownMenuCanReachEveryIndoorWorkout() {
        let model = CrownMenuScrollModel(optionCount: 5, hasBack: true, hasForward: false)

        XCTAssertEqual(model.crownLowerBound, -4)
        XCTAssertEqual(model.crownUpperBound, 1)
        XCTAssertEqual(model.action(forCrownValue: -4, currentSelectionIndex: 3), .select(4))
        XCTAssertEqual(model.action(forCrownValue: -3, currentSelectionIndex: 4), .select(3))
    }

    func testWorkoutControlPresentationForRunningPausedAndSavingStates() {
        let running = WorkoutControlPresentation(isPaused: false, isFinishing: false)
        XCTAssertNil(running.statusText)
        XCTAssertEqual(running.pauseTitle, "Pause")
        XCTAssertEqual(running.pauseSystemImage, "pause.fill")
        XCTAssertTrue(running.isPauseEnabled)
        XCTAssertEqual(running.endTitle, "End")
        XCTAssertEqual(running.endSystemImage, "stop.fill")
        XCTAssertTrue(running.isEndEnabled)

        let paused = WorkoutControlPresentation(isPaused: true, isFinishing: false)
        XCTAssertEqual(paused.statusText, "Paused")
        XCTAssertEqual(paused.pauseTitle, "Resume")
        XCTAssertEqual(paused.pauseSystemImage, "play.fill")
        XCTAssertTrue(paused.isPauseEnabled)
        XCTAssertEqual(paused.endTitle, "End")
        XCTAssertTrue(paused.isEndEnabled)

        let saving = WorkoutControlPresentation(isPaused: true, isFinishing: true)
        XCTAssertEqual(saving.statusText, "Saving")
        XCTAssertEqual(saving.pauseTitle, "Resume")
        XCTAssertFalse(saving.isPauseEnabled)
        XCTAssertEqual(saving.endTitle, "Saving")
        XCTAssertEqual(saving.endSystemImage, "hourglass")
        XCTAssertFalse(saving.isEndEnabled)
    }

    func testHeartRateDisplayPresentationUsesConfiguredZoneColors() {
        let settings = HeartRateSettings(maxHeartRate: 200, zoneBoundaries: [0.55, 0.65, 0.75, 0.85, 0.95])

        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: nil, settings: settings), HeartRateDisplayPresentation(valueText: "--", colorName: "secondary"))
        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: 110, settings: settings), HeartRateDisplayPresentation(valueText: "110", colorName: "blue"))
        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: 130, settings: settings), HeartRateDisplayPresentation(valueText: "130", colorName: "green"))
        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: 150, settings: settings), HeartRateDisplayPresentation(valueText: "150", colorName: "yellow"))
        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: 170, settings: settings), HeartRateDisplayPresentation(valueText: "170", colorName: "orange"))
        XCTAssertEqual(HeartRateDisplayPresentation(heartRate: 190, settings: settings), HeartRateDisplayPresentation(valueText: "190", colorName: "red"))
    }

    func testHeartRateSampleStatisticsUseTimeWeightedAverageAndMaximum() {
        let start = Date(timeIntervalSince1970: 900)
        let samples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 100),
            HeartRateSample(timestamp: start.addingTimeInterval(10), beatsPerMinute: 160),
            HeartRateSample(timestamp: start.addingTimeInterval(70), beatsPerMinute: 130)
        ]

        let summary = HeartRateSampleStatistics.summary(
            samples: samples,
            workoutEnd: start.addingTimeInterval(100),
            maximumSampleGap: 30
        )

        XCTAssertEqual(summary.average, 139)
        XCTAssertEqual(summary.maximum, 160)
    }

    func testHeartRateSampleStatisticsFallsBackToSampleAverageWithoutElapsedTime() {
        let start = Date(timeIntervalSince1970: 950)
        let samples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 100),
            HeartRateSample(timestamp: start, beatsPerMinute: 160)
        ]

        let summary = HeartRateSampleStatistics.summary(samples: samples, workoutEnd: start)

        XCTAssertEqual(summary.average, 130)
        XCTAssertEqual(summary.maximum, 160)
    }

    func testHeartRateZoneDurationsUseSampleGapsAndWorkoutEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 100),
            HeartRateSample(timestamp: start.addingTimeInterval(10), beatsPerMinute: 130),
            HeartRateSample(timestamp: start.addingTimeInterval(25), beatsPerMinute: 190)
        ]

        let durations = HeartRateZoneCalculator.zoneDurations(
            samples: samples,
            settings: HeartRateSettings(maxHeartRate: 200),
            workoutEnd: start.addingTimeInterval(40)
        )

        XCTAssertEqual(durations[.zone1], 10)
        XCTAssertEqual(durations[.zone2], 15)
        XCTAssertEqual(durations[.zone5], 15)
    }

    func testHeartRateZonesUseConfiguredBoundariesAndExposeBPMRanges() {
        let settings = HeartRateSettings(maxHeartRate: 200, zoneBoundaries: [0.55, 0.65, 0.75, 0.85, 0.95])

        XCTAssertEqual(HeartRateZoneCalculator.zone(for: 129, settings: settings), .zone1)
        XCTAssertEqual(HeartRateZoneCalculator.zone(for: 130, settings: settings), .zone2)
        XCTAssertEqual(HeartRateZoneCalculator.zone(for: 150, settings: settings), .zone3)
        XCTAssertEqual(HeartRateZoneCalculator.zone(for: 170, settings: settings), .zone4)
        XCTAssertEqual(HeartRateZoneCalculator.zone(for: 190, settings: settings), .zone5)

        XCTAssertEqual(HeartRateZoneCalculator.bpmRangeText(for: .zone1, settings: settings), "0-129 bpm")
        XCTAssertEqual(HeartRateZoneCalculator.bpmRangeText(for: .zone2, settings: settings), "130-149 bpm")
        XCTAssertEqual(HeartRateZoneCalculator.bpmRangeText(for: .zone5, settings: settings), "190+ bpm")
    }

    func testPaceFormattingAndUnitCalculation() {
        let pace = PaceCalculator.paceSecondsPerUnit(
            distanceMeters: DistanceUnit.miles.metersPerUnit,
            elapsedSeconds: 600,
            unit: .miles
        )

        XCTAssertEqual(pace, 600)
        XCTAssertEqual(WorkoutFormatter.pace(pace, unit: .miles), "10:00/mi")
        XCTAssertEqual(WorkoutFormatter.distance(5_000, unit: .kilometers), "5.00 km")
    }

    func testBestEffortEngineFindsFastestRollingRunSegments() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(240),
            duration: 240,
            distanceMeters: 500,
            activeEnergyKilocalories: 80,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: 100, seconds: 60, start: start),
                routePoint(distanceMeters: 200, seconds: 120, start: start),
                routePoint(distanceMeters: 300, seconds: 150, start: start),
                routePoint(distanceMeters: 400, seconds: 180, start: start),
                routePoint(distanceMeters: 500, seconds: 240, start: start)
            ]
        )

        let efforts = BestEffortEngine.fastestEfforts(workouts: [workout])

        XCTAssertEqual(try XCTUnwrap(efforts[.meters100]).duration, 30, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(efforts[.meters200]).duration, 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(efforts[.meters400]).duration, 180, accuracy: 0.001)
        XCTAssertNil(efforts[.kilometer])
        XCTAssertEqual(WorkoutFormatter.bestEffortDuration(73.24), "1:13.2")
    }

    func testBestEffortEngineSkipsExcludedWorkouts() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let excludedWorkout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            duration: 60,
            distanceMeters: 100,
            activeEnergyKilocalories: 20,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: 100, seconds: 60, start: start)
            ]
        )
        let replacementStart = start.addingTimeInterval(86_400)
        let replacementWorkout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: replacementStart,
            endDate: replacementStart.addingTimeInterval(90),
            duration: 90,
            distanceMeters: 100,
            activeEnergyKilocalories: 20,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: replacementStart),
                routePoint(distanceMeters: 100, seconds: 90, start: replacementStart)
            ]
        )

        let efforts = BestEffortEngine.fastestEfforts(
            workouts: [excludedWorkout, replacementWorkout],
            excluding: [excludedWorkout.id]
        )

        XCTAssertEqual(efforts[.meters100]?.workoutID, replacementWorkout.id)
        XCTAssertEqual(efforts[.meters100]?.duration, 90)
    }

    func testBestEffortEngineExcludesRecordedPauseTime() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(360),
            duration: 60,
            distanceMeters: 100,
            activeEnergyKilocalories: 20,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: 50, seconds: 30, start: start),
                routePoint(distanceMeters: 50, seconds: 330, start: start),
                routePoint(distanceMeters: 100, seconds: 360, start: start)
            ],
            recordedPauseRanges: [
                DateRangeValue(start: start.addingTimeInterval(30), end: start.addingTimeInterval(330))
            ]
        )

        let efforts = BestEffortEngine.fastestEfforts(workouts: [workout])

        XCTAssertEqual(try XCTUnwrap(efforts[.meters100]).duration, 60, accuracy: 0.001)
    }

    func testBestEffortEngineRejectsGPSJumpsAndUsesPlausibleRoute() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(62),
            duration: 62,
            distanceMeters: 100,
            activeEnergyKilocalories: 20,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: 1_000, seconds: 1, start: start),
                routePoint(distanceMeters: 0, seconds: 2, start: start),
                routePoint(distanceMeters: 100, seconds: 62, start: start)
            ]
        )

        let efforts = BestEffortEngine.fastestEfforts(workouts: [workout])

        XCTAssertEqual(try XCTUnwrap(efforts[.meters100]).duration, 60, accuracy: 0.001)
    }

    func testBestEffortEngineDoesNotCreateRecordsFromOnlyGPSJump() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1),
            duration: 1,
            distanceMeters: 1_000,
            activeEnergyKilocalories: 1,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: 1_000, seconds: 1, start: start)
            ]
        )

        XCTAssertTrue(BestEffortEngine.fastestEfforts(workouts: [workout]).isEmpty)
    }

    func testBestEffortCacheKeepsAllTimeWinnerAndRevealsNextAfterExclusion() throws {
        let fastWorkoutID = UUID()
        let slowerWorkoutID = UUID()
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var cache = BestEffortCache()
        cache.store(
            workoutID: fastWorkoutID,
            workoutStartDate: start,
            efforts: [
                .meters100: BestEffortResult(
                    distance: .meters100,
                    workoutID: fastWorkoutID,
                    workoutStartDate: start,
                    duration: 12,
                    segmentStart: start,
                    segmentEnd: start.addingTimeInterval(12)
                )
            ]
        )
        cache.store(
            workoutID: slowerWorkoutID,
            workoutStartDate: start.addingTimeInterval(86_400),
            efforts: [
                .meters100: BestEffortResult(
                    distance: .meters100,
                    workoutID: slowerWorkoutID,
                    workoutStartDate: start.addingTimeInterval(86_400),
                    duration: 15,
                    segmentStart: start.addingTimeInterval(86_400),
                    segmentEnd: start.addingTimeInterval(86_415)
                )
            ]
        )

        XCTAssertEqual(try XCTUnwrap(cache.fastestEfforts()[.meters100]).workoutID, fastWorkoutID)
        XCTAssertEqual(
            try XCTUnwrap(cache.fastestEfforts(excluding: [fastWorkoutID])[.meters100]).workoutID,
            slowerWorkoutID
        )
    }

    func testRollingPaceRefreshCadenceUsesConfiguredWindow() {
        XCTAssertTrue(PaceCalculator.shouldRefreshDisplayedPace(
            elapsedSeconds: 1,
            lastRefreshElapsedSeconds: nil,
            mode: .rolling,
            rollingPaceSeconds: 30
        ))
        XCTAssertFalse(PaceCalculator.shouldRefreshDisplayedPace(
            elapsedSeconds: 29,
            lastRefreshElapsedSeconds: 0,
            mode: .rolling,
            rollingPaceSeconds: 30
        ))
        XCTAssertTrue(PaceCalculator.shouldRefreshDisplayedPace(
            elapsedSeconds: 30,
            lastRefreshElapsedSeconds: 0,
            mode: .rolling,
            rollingPaceSeconds: 30
        ))
        XCTAssertTrue(PaceCalculator.shouldRefreshDisplayedPace(
            elapsedSeconds: 5,
            lastRefreshElapsedSeconds: 0,
            mode: .wholeWorkout,
            rollingPaceSeconds: 30
        ))
    }

    func testIntervalTimelineReportsCurrentStepAndCompletion() {
        let workout = IntervalWorkout(
            name: "Test Intervals",
            warmupSeconds: 60,
            repeats: 2,
            work: IntervalStep(label: "Push", durationSeconds: 30, intensity: .hard),
            recovery: IntervalStep(label: "Recover", durationSeconds: 15, intensity: .easy),
            cooldownSeconds: 45
        )

        let progress = IntervalTimeline.progress(for: workout, elapsedSeconds: 70)
        XCTAssertEqual(progress.title, "Push")
        XCTAssertEqual(progress.detail, "Rep 1 of 2")
        XCTAssertEqual(progress.stepIndex, 2)
        XCTAssertEqual(progress.stepCount, 6)
        XCTAssertEqual(progress.remainingInStep, 20)
        XCTAssertEqual(progress.intensity, .hard)
        XCTAssertFalse(progress.isComplete)

        let complete = IntervalTimeline.progress(for: workout, elapsedSeconds: 195)
        XCTAssertTrue(complete.isComplete)
        XCTAssertEqual(complete.title, "Complete")
    }

    func testSettingsStoreStartsWithNoProgrammedIntervalsAndRoundTripsSavedIntervals() throws {
        let suiteName = "TrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.loadIntervals(), [])

        let workout = IntervalWorkout(
            name: "Track 8 x 400",
            warmupSeconds: 900,
            repeats: 8,
            work: IntervalStep(label: "400", durationSeconds: 90, intensity: .hard),
            recovery: IntervalStep(label: "Jog", durationSeconds: 75, intensity: .easy),
            cooldownSeconds: 600
        )

        store.saveIntervals([workout])
        XCTAssertEqual(store.loadIntervals(), [workout])
    }

    func testSettingsStoreRoundTripsDeletedWorkoutIDs() throws {
        let suiteName = "TrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.loadDeletedWorkoutIDs(), [])

        let deletedIDs: Set<UUID> = [UUID(), UUID()]
        store.saveDeletedWorkoutIDs(deletedIDs)
        XCTAssertEqual(store.loadDeletedWorkoutIDs(), deletedIDs)
    }

    func testSettingsStoreRoundTripsBestEffortExclusions() throws {
        let suiteName = "TrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.loadExcludedBestEffortWorkoutIDs(), [])

        let excludedIDs: Set<UUID> = [UUID(), UUID()]
        store.saveExcludedBestEffortWorkoutIDs(excludedIDs)
        XCTAssertEqual(store.loadExcludedBestEffortWorkoutIDs(), excludedIDs)
    }

    func testSettingsStoreRoundTripsBestEffortCache() throws {
        let suiteName = "TrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workoutID = UUID()
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let result = BestEffortResult(
            distance: .kilometer,
            workoutID: workoutID,
            workoutStartDate: start,
            duration: 240,
            segmentStart: start,
            segmentEnd: start.addingTimeInterval(240)
        )
        var cache = BestEffortCache()
        cache.store(workoutID: workoutID, workoutStartDate: start, efforts: [.kilometer: result])

        let store = SettingsStore(defaults: defaults)
        store.saveBestEffortCache(cache)

        XCTAssertEqual(store.loadBestEffortCache(), cache)
    }

    func testWorkoutSettingsDecodeOldPayloadWithNewDefaults() throws {
        let json = """
        {
          "distanceUnit": "kilometers",
          "paceMode": "wholeWorkout",
          "rollingPaceSeconds": 45,
          "outdoorOrder": ["outdoorRun", "outdoorWalk", "outdoorBike"],
          "indoorOrder": ["indoorRun", "indoorWalk", "indoorElliptical", "indoorBike", "weights"],
          "heartRate": {
            "maxHeartRate": 185,
            "zoneBoundaries": [0.50, 0.60, 0.70, 0.80, 0.90]
          },
          "userMetrics": {
            "age": 45,
            "heightCentimeters": 180,
            "weightKilograms": 75,
            "restingHeartRate": 55
          },
          "stravaAutoUpload": false
        }
        """

        let settings = try JSONDecoder().decode(WorkoutSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.distanceUnit, .kilometers)
        XCTAssertEqual(settings.splitAnnouncementUnit, .kilometers)
        XCTAssertEqual(settings.bodyMeasurementUnit, .imperial)
        XCTAssertEqual(settings.paceMode, .wholeWorkout)
        XCTAssertEqual(settings.rollingPaceSeconds, 45)
        XCTAssertTrue(settings.touchControlsEnabled)
        XCTAssertTrue(settings.autoDisableTouchOnWorkoutStart)
        XCTAssertNil(settings.userMetrics.knownVO2Max)
        XCTAssertFalse(settings.stravaAutoUpload)
    }

    func testWorkoutSettingsRoundTripsDisabledAnnouncements() throws {
        var settings = WorkoutSettings.defaults
        settings.splitAnnouncementUnit = .off

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WorkoutSettings.self, from: data)

        XCTAssertEqual(decoded.splitAnnouncementUnit, .off)
    }

    func testDistanceSplitAnnouncementsUsePerSplitPaceAndSelectedUnit() {
        var tracker = DistanceSplitAnnouncementTracker()

        XCTAssertTrue(tracker.announcements(
            distanceMeters: 1_000,
            elapsedSeconds: 300,
            unit: .miles
        ).isEmpty)

        let firstMile = tracker.announcements(
            distanceMeters: DistanceUnit.miles.metersPerUnit,
            elapsedSeconds: 493,
            unit: .miles
        )
        XCTAssertEqual(firstMile, [DistanceSplitAnnouncement(unitNumber: 1, splitSeconds: 493, unit: .miles)])
        XCTAssertEqual(firstMile.first?.spokenText, "Mile 1, 8 minutes 13 seconds per mile")

        let secondMile = tracker.announcements(
            distanceMeters: DistanceUnit.miles.metersPerUnit * 2,
            elapsedSeconds: 982,
            unit: .miles
        )
        XCTAssertEqual(secondMile, [DistanceSplitAnnouncement(unitNumber: 2, splitSeconds: 489, unit: .miles)])
        XCTAssertEqual(secondMile.first?.spokenText, "Mile 2, 8 minutes 9 seconds per mile")
    }

    func testDistanceSplitAnnouncementsHandleMultipleKilometerBoundaries() {
        var tracker = DistanceSplitAnnouncementTracker()

        let announcements = tracker.announcements(
            distanceMeters: 2_000,
            elapsedSeconds: 600,
            unit: .kilometers
        )

        XCTAssertEqual(announcements, [
            DistanceSplitAnnouncement(unitNumber: 1, splitSeconds: 300, unit: .kilometers),
            DistanceSplitAnnouncement(unitNumber: 2, splitSeconds: 300, unit: .kilometers)
        ])
        XCTAssertEqual(announcements.last?.spokenText, "Kilometer 2, 5 minutes per kilometer")
    }

    func testWatchWorkoutCompletionPayloadRoundTrips() throws {
        let completion = WatchWorkoutCompletion(
            id: UUID(),
            workoutID: UUID(),
            activity: .outdoorRun,
            endedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        XCTAssertEqual(WatchWorkoutCompletion(payload: completion.payload), completion)

        var legacyPayload = completion.payload
        legacyPayload.removeValue(forKey: WatchConnectivityPayloadKey.completionID)
        XCTAssertEqual(WatchWorkoutCompletion(payload: legacyPayload)?.id, completion.workoutID)
    }

    func testSettingsWriterUpdatesTouchControlsAndPostsNotification() throws {
        let suiteName = "TrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SettingsStore(defaults: defaults)
        let notification = expectation(description: "settings changed")
        var notifiedSettings: WorkoutSettings?
        let observer = NotificationCenter.default.addObserver(
            forName: TrackerSettingsChange.notificationName,
            object: nil,
            queue: nil
        ) { note in
            notifiedSettings = TrackerSettingsChange.settings(from: note)
            notification.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let updated = TrackerSettingsWriter.setTouchControlsEnabled(false, store: store)

        wait(for: [notification], timeout: 1)
        XCTAssertFalse(updated.touchControlsEnabled)
        XCTAssertFalse(store.loadSettings().touchControlsEnabled)
        XCTAssertEqual(notifiedSettings?.touchControlsEnabled, false)
    }

    func testIntervalWorkoutDraftNormalizesLabelsAndRangesForSavedWorkouts() throws {
        let draft = IntervalWorkoutDraft(
            name: "  Track 400s  ",
            warmupMinutes: -4,
            repeats: 99,
            workLabel: "  ",
            workSeconds: 22,
            workIntensity: .hard,
            recoveryLabel: "  Jog  ",
            recoverySeconds: 2_400,
            recoveryIntensity: .easy,
            cooldownMinutes: 90
        )
        let workoutID = UUID()
        let workID = UUID()
        let recoveryID = UUID()
        let workout = try XCTUnwrap(draft.workout(id: workoutID, workID: workID, recoveryID: recoveryID))

        XCTAssertEqual(workout.id, workoutID)
        XCTAssertEqual(workout.name, "Track 400s")
        XCTAssertEqual(workout.warmupSeconds, 0)
        XCTAssertEqual(workout.repeats, 30)
        XCTAssertEqual(workout.work.id, workID)
        XCTAssertEqual(workout.work.label, "Run")
        XCTAssertEqual(workout.work.durationSeconds, 15)
        XCTAssertEqual(workout.work.intensity, .hard)
        XCTAssertEqual(workout.recovery.id, recoveryID)
        XCTAssertEqual(workout.recovery.label, "Jog")
        XCTAssertEqual(workout.recovery.durationSeconds, 1_800)
        XCTAssertEqual(workout.cooldownSeconds, 3_600)
        XCTAssertEqual(workout.totalSeconds, 58_050)
        XCTAssertEqual(draft.totalSeconds, 58_050)
    }

    func testIntervalWorkoutDraftRejectsBlankWorkoutName() {
        let draft = IntervalWorkoutDraft(name: "   ")

        XCTAssertFalse(draft.canBuildWorkout)
        XCTAssertNil(draft.workout())
    }

    func testWeeklySummaryAggregatesActivityTotalsActiveDaysAndWeightedHeartRate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let runStart = week.start.addingTimeInterval(12 * 3600)
        let bikeStart = week.start.addingTimeInterval(36 * 3600)
        let weightsStart = week.start.addingTimeInterval(37 * 3600)
        let previousWeekStart = week.start.addingTimeInterval(-4 * 3600)

        let run = WorkoutSummary(
            activity: .outdoorRun,
            startDate: runStart,
            endDate: runStart.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 420,
            averageHeartRate: 150,
            heartRateSamples: [
                HeartRateSample(timestamp: runStart, beatsPerMinute: 100),
                HeartRateSample(timestamp: runStart.addingTimeInterval(10), beatsPerMinute: 130),
                HeartRateSample(timestamp: runStart.addingTimeInterval(25), beatsPerMinute: 190)
            ]
        )
        let bike = WorkoutSummary(
            activity: .outdoorBike,
            startDate: bikeStart,
            endDate: bikeStart.addingTimeInterval(3_600),
            duration: 3_600,
            distanceMeters: 10_000,
            activeEnergyKilocalories: 600,
            averageHeartRate: 120
        )
        let weights = WorkoutSummary(
            activity: .weights,
            startDate: weightsStart,
            endDate: weightsStart.addingTimeInterval(900),
            duration: 900,
            distanceMeters: 0,
            activeEnergyKilocalories: 110
        )
        let previousWeekRun = WorkoutSummary(
            activity: .outdoorRun,
            startDate: previousWeekStart,
            endDate: previousWeekStart.addingTimeInterval(1_200),
            duration: 1_200,
            distanceMeters: 3_000,
            activeEnergyKilocalories: 300,
            averageHeartRate: 180
        )

        let summary = SummaryEngine.currentWeekSummary(
            workouts: [run, bike, weights, previousWeekRun],
            heartRateSettings: HeartRateSettings(maxHeartRate: 200),
            calendar: calendar
        )

        XCTAssertEqual(summary.workoutCount, 3)
        XCTAssertEqual(summary.activeDays, 2)
        XCTAssertEqual(summary.totalTime, 6_300)
        XCTAssertEqual(summary.totalDistanceMeters, 15_000)
        XCTAssertEqual(summary.activeCalories, 1_130)
        XCTAssertEqual(summary.averageHeartRate, 130)
        XCTAssertEqual(summary.timeByActivity[.outdoorRun], 1_800)
        XCTAssertEqual(summary.timeByActivity[.outdoorBike], 3_600)
        XCTAssertEqual(summary.timeByActivity[.weights], 900)
        XCTAssertEqual(summary.distanceByActivity[.outdoorRun], 5_000)
        XCTAssertEqual(summary.distanceByActivity[.outdoorBike], 10_000)
        XCTAssertEqual(summary.distanceByActivity[.weights], 0)
        XCTAssertEqual(summary.heartRateZoneDurations[.zone1], 10)
        XCTAssertEqual(summary.heartRateZoneDurations[.zone2], 15)
        XCTAssertEqual(summary.heartRateZoneDurations[.zone5], 30)
    }

    func testSummaryPeriodFormatterUsesReadableSameMonthDateRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))

        let label = SummaryPeriodFormatter.dateRangeText(
            for: DateInterval(start: start, end: end),
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label, "July 5 - 11, 2026")
    }

    func testSummaryPeriodFormatterUsesReadableCrossMonthDateRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))

        let label = SummaryPeriodFormatter.dateRangeText(
            for: DateInterval(start: start, end: end),
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label, "June 29 - July 5, 2026")
    }

    func testHealthKitActiveCaloriesAreNotBMRAdjustedAgain() {
        let activeCalories = WorkoutCalories.activeKilocalories(fromHealthKitActiveKilocalories: 400)

        XCTAssertEqual(activeCalories, 400)
    }

    func testGrossCalorieEstimateSubtractsEstimatedBasalCalories() {
        let metrics = UserMetrics(
            age: 40,
            biologicalSex: .male,
            heightCentimeters: 180,
            weightKilograms: 80
        )

        let activeCalories = WorkoutCalories.activeKilocalories(
            fromGrossKilocalorieEstimate: 500,
            duration: 3_600,
            userMetrics: metrics
        )

        XCTAssertEqual(activeCalories, 427.92, accuracy: 0.01)
    }

    func testGrossCalorieEstimateClampsAtZeroAfterBasalSubtraction() {
        let activeCalories = WorkoutCalories.activeKilocalories(
            fromGrossKilocalorieEstimate: 20,
            duration: 3_600,
            userMetrics: UserMetrics(weightKilograms: 80)
        )

        XCTAssertEqual(activeCalories, 0)
    }

    func testPauseDetectionAndEditApplicationTrimAndShiftWorkoutData() {
        let start = Date(timeIntervalSince1970: 2_000)
        let route = [
            routePoint(seconds: 0, latitude: 37.0000, start: start),
            routePoint(seconds: 20, latitude: 37.0001, start: start),
            routePoint(seconds: 40, latitude: 37.0001, start: start),
            routePoint(seconds: 60, latitude: 37.0001, start: start),
            routePoint(seconds: 80, latitude: 37.0006, start: start),
            routePoint(seconds: 120, latitude: 37.0010, start: start)
        ]
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            distanceMeters: 1_000,
            activeEnergyKilocalories: 100,
            averageHeartRate: 120,
            maxHeartRate: 150,
            route: route,
            heartRateSamples: [
                HeartRateSample(timestamp: start.addingTimeInterval(20), beatsPerMinute: 100),
                HeartRateSample(timestamp: start.addingTimeInterval(50), beatsPerMinute: 130),
                HeartRateSample(timestamp: start.addingTimeInterval(90), beatsPerMinute: 140)
            ]
        )

        let pauses = PauseDetector.candidatePauseRanges(route: route, minimumDuration: 30, radiusMeters: 20)
        XCTAssertEqual(pauses.count, 1)
        XCTAssertEqual(pauses[0].lowerBound, start)
        XCTAssertEqual(pauses[0].upperBound, start.addingTimeInterval(60))

        let edit = ActivityEdit(
            workoutID: workout.id,
            trimStartSeconds: 10,
            trimEndSeconds: 20,
            removedPauses: [DateRangeValue(start: start.addingTimeInterval(30), end: start.addingTimeInterval(60))]
        )
        let adjusted = WorkoutEditApplier.adjustedWorkout(workout, edit: edit)

        XCTAssertEqual(WorkoutEditApplier.removedPauseSeconds(for: workout, edit: edit), 30)
        XCTAssertEqual(adjusted.startDate, start.addingTimeInterval(10))
        XCTAssertEqual(adjusted.endDate, start.addingTimeInterval(70))
        XCTAssertEqual(adjusted.duration, 60)
        XCTAssertEqual(adjusted.activeEnergyKilocalories, 50, accuracy: 0.01)
        XCTAssertEqual(adjusted.averageHeartRate, 110)
        XCTAssertEqual(adjusted.maxHeartRate, 140)
        XCTAssertEqual(adjusted.heartRateSamples.map(\.beatsPerMinute), [100, 140])
        XCTAssertEqual(adjusted.heartRateSamples.last?.timestamp, start.addingTimeInterval(60))
    }

    func testWorkoutEditKeepsRecordedPauseTimeExcluded() {
        let start = Date(timeIntervalSince1970: 2_300)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(180),
            duration: 120,
            distanceMeters: 1_000,
            activeEnergyKilocalories: 120,
            recordedPauseRanges: [
                DateRangeValue(start: start.addingTimeInterval(60), end: start.addingTimeInterval(120))
            ]
        )
        let edit = ActivityEdit(workoutID: workout.id, trimEndSeconds: 10)

        let adjusted = WorkoutEditApplier.adjustedWorkout(workout, edit: edit)

        XCTAssertEqual(adjusted.duration, 110)
        XCTAssertEqual(adjusted.endDate, start.addingTimeInterval(110))
        XCTAssertTrue(adjusted.recordedPauseRanges.isEmpty)
    }

    func testSplitBuilderBuildsRouteBasedMileSplits() {
        let start = Date(timeIntervalSince1970: 2_500)
        let totalDistance = DistanceUnit.miles.metersPerUnit * 2.5
        let route = [
            routePoint(distanceMeters: 0, seconds: 0, start: start),
            routePoint(distanceMeters: totalDistance, seconds: 1_500, start: start)
        ]
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_500),
            duration: 1_500,
            distanceMeters: totalDistance,
            activeEnergyKilocalories: 300,
            route: route
        )

        let splits = SplitBuilder.splits(for: workout, unit: .miles)

        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].distanceMeters, DistanceUnit.miles.metersPerUnit, accuracy: 0.01)
        XCTAssertEqual(splits[1].distanceMeters, DistanceUnit.miles.metersPerUnit, accuracy: 0.01)
        XCTAssertEqual(splits[2].distanceMeters, DistanceUnit.miles.metersPerUnit * 0.5, accuracy: 0.01)
        XCTAssertEqual(splits[0].paceSecondsPerUnit ?? 0, 600, accuracy: 0.01)
        XCTAssertEqual(splits[2].paceSecondsPerUnit ?? 0, 600, accuracy: 0.01)
    }

    func testSplitBuilderExcludesRecordedPauseTimeAndDistance() {
        let start = Date(timeIntervalSince1970: 2_700)
        let mile = DistanceUnit.miles.metersPerUnit
        let pausedMovement = 200.0
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_260),
            duration: 960,
            distanceMeters: mile * 2,
            activeEnergyKilocalories: 250,
            route: [
                routePoint(distanceMeters: 0, seconds: 0, start: start),
                routePoint(distanceMeters: mile * 0.5, seconds: 240, start: start),
                routePoint(distanceMeters: mile * 0.5 + pausedMovement, seconds: 540, start: start),
                routePoint(distanceMeters: mile + pausedMovement, seconds: 780, start: start),
                routePoint(distanceMeters: mile * 1.5 + pausedMovement, seconds: 1_020, start: start),
                routePoint(distanceMeters: mile * 2 + pausedMovement, seconds: 1_260, start: start)
            ],
            recordedPauseRanges: [
                DateRangeValue(start: start.addingTimeInterval(240), end: start.addingTimeInterval(540))
            ]
        )

        let splits = SplitBuilder.splits(for: workout, unit: .miles)

        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].distanceMeters, mile, accuracy: 0.01)
        XCTAssertEqual(splits[1].distanceMeters, mile, accuracy: 0.01)
        XCTAssertEqual(splits[0].paceSecondsPerUnit ?? 0, 480, accuracy: 0.01)
        XCTAssertEqual(splits[1].paceSecondsPerUnit ?? 0, 480, accuracy: 0.01)
    }

    func testSplitBuilderFallsBackToProportionalKilometerSplitsWithoutRoute() {
        let start = Date(timeIntervalSince1970: 2_800)
        let workout = WorkoutSummary(
            activity: .indoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_250),
            duration: 1_250,
            distanceMeters: 2_500,
            activeEnergyKilocalories: 240
        )

        let splits = SplitBuilder.splits(for: workout, unit: .kilometers)

        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].distanceMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(splits[1].distanceMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(splits[2].distanceMeters, 500, accuracy: 0.01)
        XCTAssertEqual(splits[0].paceSecondsPerUnit ?? 0, 500, accuracy: 0.01)
        XCTAssertEqual(splits[2].paceSecondsPerUnit ?? 0, 500, accuracy: 0.01)
    }

    func testWorkoutSummaryDecodesWithoutRecordedPauseRanges() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            duration: 60,
            distanceMeters: 100,
            activeEnergyKilocalories: 20,
            recordedPauseRanges: [
                DateRangeValue(start: start.addingTimeInterval(20), end: start.addingTimeInterval(30))
            ]
        )
        let encoded = try JSONEncoder().encode(workout)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload.removeValue(forKey: "recordedPauseRanges")

        let decoded = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertTrue(decoded.recordedPauseRanges.isEmpty)
    }

    func testVO2HistoryUsesRecentEligibleOutdoorRunWalkWorkouts() {
        let start = Date(timeIntervalSince1970: 3_000)
        let settings = HeartRateSettings(maxHeartRate: 190)
        let metrics = UserMetrics(age: 40)
        let olderRun = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 400,
            averageHeartRate: 150
        )
        let recentRun = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start.addingTimeInterval(86_400),
            endDate: start.addingTimeInterval(86_400 + 1_500),
            duration: 1_500,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 410,
            averageHeartRate: 148
        )
        let indoorRun = WorkoutSummary(
            activity: .indoorRun,
            startDate: start.addingTimeInterval(172_800),
            endDate: start.addingTimeInterval(174_300),
            duration: 1_500,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 390,
            averageHeartRate: 145
        )

        let history = VO2MaxEstimator.history(
            workouts: [olderRun, recentRun, indoorRun],
            userMetrics: metrics,
            settings: settings
        )

        XCTAssertNotNil(history)
        XCTAssertEqual(history?.points.count, 2)
        XCTAssertEqual(history?.points.first?.workoutID, recentRun.id)
        XCTAssertNil(VO2MaxEstimator.estimate(workout: indoorRun, userMetrics: metrics, settings: settings))
    }

    func testVO2EstimateUsesRestingHeartRateAndBodyMetrics() throws {
        let start = Date(timeIntervalSince1970: 3_500)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_500),
            duration: 1_500,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 420,
            averageHeartRate: 150
        )
        let settings = HeartRateSettings(maxHeartRate: 190)
        let baseline = try XCTUnwrap(VO2MaxEstimator.estimate(
            workout: workout,
            userMetrics: UserMetrics(age: 40),
            settings: settings
        ))
        let fitMetricsEstimate = try XCTUnwrap(VO2MaxEstimator.estimate(
            workout: workout,
            userMetrics: UserMetrics(age: 40, biologicalSex: .male, heightCentimeters: 180, weightKilograms: 72, restingHeartRate: 45),
            settings: settings
        ))
        let higherRiskMetricsEstimate = try XCTUnwrap(VO2MaxEstimator.estimate(
            workout: workout,
            userMetrics: UserMetrics(age: 40, biologicalSex: .female, heightCentimeters: 160, weightKilograms: 100, restingHeartRate: 85),
            settings: settings
        ))

        XCTAssertGreaterThan(fitMetricsEstimate, baseline)
        XCTAssertGreaterThan(fitMetricsEstimate, higherRiskMetricsEstimate)
    }

    func testVO2EstimateUsesKnownValueToCalibrateLowSubmaxEstimate() throws {
        let start = Date(timeIntervalSince1970: 3_600)
        let workout = WorkoutSummary(
            activity: .outdoorWalk,
            startDate: start,
            endDate: start.addingTimeInterval(900),
            duration: 900,
            distanceMeters: 1_000,
            activeEnergyKilocalories: 90,
            averageHeartRate: 100
        )
        let settings = HeartRateSettings(maxHeartRate: 190)
        let uncalibrated = try XCTUnwrap(VO2MaxEstimator.estimate(
            workout: workout,
            userMetrics: UserMetrics(age: 40),
            settings: settings
        ))
        let calibrated = try XCTUnwrap(VO2MaxEstimator.estimate(
            workout: workout,
            userMetrics: UserMetrics(age: 40, knownVO2Max: 50),
            settings: settings
        ))

        XCTAssertGreaterThan(calibrated, uncalibrated + 10)
        XCTAssertEqual(calibrated, 50, accuracy: 0.1)
    }

    func testWorkoutExporterBuildsRouteTCXWithPositionAltitudeDistanceAndTimeBoundNearestHeartRate() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        let route = [
            RoutePoint(
                latitude: 37.0,
                longitude: -122.0,
                altitudeMeters: 10,
                timestamp: start,
                horizontalAccuracy: 5
            ),
            RoutePoint(
                latitude: 37.0005,
                longitude: -122.0,
                altitudeMeters: 12,
                timestamp: start.addingTimeInterval(60),
                horizontalAccuracy: 5
            ),
            RoutePoint(
                latitude: 37.0010,
                longitude: -122.0,
                altitudeMeters: 13,
                timestamp: start.addingTimeInterval(120),
                horizontalAccuracy: 5
            )
        ]
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            distanceMeters: 111.2,
            activeEnergyKilocalories: 42,
            route: route,
            heartRateSamples: [
                HeartRateSample(timestamp: start.addingTimeInterval(2), beatsPerMinute: 111),
                HeartRateSample(timestamp: start.addingTimeInterval(58), beatsPerMinute: 150),
                HeartRateSample(timestamp: start.addingTimeInterval(300), beatsPerMinute: 180)
            ]
        )

        let xml = try XCTUnwrap(String(data: WorkoutExporter().tcxData(for: workout), encoding: .utf8))

        XCTAssertTrue(xml.contains(#"<Activity Sport="Running">"#))
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>120</TotalTimeSeconds>"))
        XCTAssertTrue(xml.contains("<DistanceMeters>111.2</DistanceMeters>"))
        XCTAssertTrue(xml.contains("<LatitudeDegrees>37.0</LatitudeDegrees>"))
        XCTAssertTrue(xml.contains("<LongitudeDegrees>-122.0</LongitudeDegrees>"))
        XCTAssertTrue(xml.contains("<AltitudeMeters>10.0</AltitudeMeters>"))
        XCTAssertTrue(xml.contains("<AltitudeMeters>12.0</AltitudeMeters>"))
        XCTAssertTrue(xml.contains("<AltitudeMeters>13.0</AltitudeMeters>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>111</Value></HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>150</Value></HeartRateBpm>"))
        XCTAssertFalse(xml.contains("<HeartRateBpm><Value>180</Value></HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<DistanceMeters>0.0</DistanceMeters>"))
    }

    func testWorkoutExporterBuildsHeartRateOnlyTCXWhenRouteIsMissing() throws {
        let start = Date(timeIntervalSince1970: 5_000)
        let workout = WorkoutSummary(
            activity: .indoorBike,
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            distanceMeters: 0,
            activeEnergyKilocalories: 75,
            heartRateSamples: [
                HeartRateSample(timestamp: start.addingTimeInterval(30), beatsPerMinute: 120),
                HeartRateSample(timestamp: start.addingTimeInterval(90), beatsPerMinute: 132)
            ]
        )

        let xml = try XCTUnwrap(String(data: WorkoutExporter().tcxData(for: workout), encoding: .utf8))

        XCTAssertTrue(xml.contains(#"<Activity Sport="Biking">"#))
        XCTAssertTrue(xml.contains("<Calories>75</Calories>"))
        XCTAssertFalse(xml.contains("<Position>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>120</Value></HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>132</Value></HeartRateBpm>"))
    }

    func testStravaManualRetryPollsInFlightUploadAndFreshensFailedUploads() throws {
        let now = Date(timeIntervalSince1970: 6_000)
        let workout = WorkoutSummary(
            activity: .outdoorRun,
            startDate: now,
            endDate: now.addingTimeInterval(600),
            duration: 600,
            distanceMeters: 1_600,
            activeEnergyKilocalories: 120
        )

        let inFlight = StravaUploadRecord(
            workoutID: workout.id,
            status: .processing,
            stravaUploadID: "upload-1",
            stravaActivityID: "old-activity",
            lastError: "old error"
        )
        let inFlightRetry = try XCTUnwrap(StravaUploadPlanner.recordForManualRetry(workout: workout, existing: inFlight, now: now))
        XCTAssertEqual(inFlightRetry.status, .processing)
        XCTAssertEqual(inFlightRetry.stravaUploadID, "upload-1")
        XCTAssertNil(inFlightRetry.stravaActivityID)
        XCTAssertNil(inFlightRetry.lastError)
        XCTAssertEqual(inFlightRetry.updatedAt, now)
        XCTAssertEqual(StravaUploadPlanner.uploadIDToPoll(for: inFlight), "upload-1")

        let failed = StravaUploadRecord(
            workoutID: workout.id,
            status: .failed,
            stravaUploadID: "stale-upload",
            stravaActivityID: "stale-activity",
            lastError: "bad file"
        )
        let failedRetry = try XCTUnwrap(StravaUploadPlanner.recordForManualRetry(workout: workout, existing: failed, now: now))
        XCTAssertEqual(failedRetry.status, .pending)
        XCTAssertNil(failedRetry.stravaUploadID)
        XCTAssertNil(failedRetry.stravaActivityID)
        XCTAssertNil(failedRetry.lastError)
        XCTAssertNil(StravaUploadPlanner.uploadIDToPoll(for: failed))

        let uploaded = StravaUploadRecord(
            workoutID: workout.id,
            status: .uploaded,
            stravaUploadID: "upload-2",
            stravaActivityID: "activity-2"
        )
        XCTAssertNil(StravaUploadPlanner.recordForManualRetry(workout: workout, existing: uploaded, now: now))

        let demoWorkout = WorkoutSummary(
            source: .demo,
            activity: .outdoorRun,
            startDate: now,
            endDate: now.addingTimeInterval(600),
            duration: 600,
            distanceMeters: 1_600,
            activeEnergyKilocalories: 120
        )
        XCTAssertNil(StravaUploadPlanner.recordForManualRetry(workout: demoWorkout, existing: nil, now: now))
    }

    func testStravaAutoUploadAfterLocalEditQueuesFreshPendingOnlyWhenSafe() throws {
        let now = Date(timeIntervalSince1970: 6_500)
        let workout = WorkoutSummary(
            activity: .outdoorBike,
            startDate: now,
            endDate: now.addingTimeInterval(1_200),
            duration: 1_200,
            distanceMeters: 8_000,
            activeEnergyKilocalories: 240
        )

        let newUpload = try XCTUnwrap(StravaUploadPlanner.recordAfterSavingLocalEdit(
            workout: workout,
            autoUploadEnabled: true,
            existing: nil,
            now: now
        ))
        XCTAssertEqual(newUpload.status, .pending)
        XCTAssertNil(newUpload.stravaUploadID)

        let failed = StravaUploadRecord(workoutID: workout.id, status: .failed, stravaUploadID: "stale-upload", lastError: "bad file")
        let retried = try XCTUnwrap(StravaUploadPlanner.recordAfterSavingLocalEdit(
            workout: workout,
            autoUploadEnabled: true,
            existing: failed,
            now: now
        ))
        XCTAssertEqual(retried.status, .pending)
        XCTAssertNil(retried.stravaUploadID)
        XCTAssertNil(retried.lastError)

        let processing = StravaUploadRecord(workoutID: workout.id, status: .processing, stravaUploadID: "upload-3")
        XCTAssertNil(StravaUploadPlanner.recordAfterSavingLocalEdit(workout: workout, autoUploadEnabled: true, existing: processing, now: now))

        let uploaded = StravaUploadRecord(workoutID: workout.id, status: .uploaded, stravaUploadID: "upload-4", stravaActivityID: "activity-4")
        XCTAssertNil(StravaUploadPlanner.recordAfterSavingLocalEdit(workout: workout, autoUploadEnabled: true, existing: uploaded, now: now))
        XCTAssertNil(StravaUploadPlanner.recordAfterSavingLocalEdit(workout: workout, autoUploadEnabled: false, existing: nil, now: now))

        let demoWorkout = WorkoutSummary(
            source: .demo,
            activity: .outdoorBike,
            startDate: now,
            endDate: now.addingTimeInterval(1_200),
            duration: 1_200,
            distanceMeters: 8_000,
            activeEnergyKilocalories: 240
        )
        XCTAssertNil(StravaUploadPlanner.recordAfterSavingLocalEdit(workout: demoWorkout, autoUploadEnabled: true, existing: nil, now: now))
    }

#if canImport(HealthKit)
    func testHealthKitWorkoutClassifierMapsOnlySupportedV1Activities() {
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .running, isIndoor: false), .outdoorRun)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .running, isIndoor: true), .indoorRun)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .walking, isIndoor: false), .outdoorWalk)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .hiking, isIndoor: false), .outdoorWalk)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .cycling, isIndoor: true), .indoorBike)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .elliptical, isIndoor: true), .indoorElliptical)
        XCTAssertEqual(WorkoutActivity.fromHealthKit(activityType: .traditionalStrengthTraining, isIndoor: true), .weights)
        XCTAssertNil(WorkoutActivity.fromHealthKit(activityType: .swimming, isIndoor: false))
        XCTAssertNil(WorkoutActivity.fromHealthKit(activityType: .yoga, isIndoor: true))
    }
#endif

    private func routePoint(seconds: TimeInterval, latitude: Double, start: Date) -> RoutePoint {
        RoutePoint(
            latitude: latitude,
            longitude: -122.0,
            altitudeMeters: nil,
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracy: 5
        )
    }

    private func routePoint(distanceMeters: Double, seconds: TimeInterval, start: Date) -> RoutePoint {
        RoutePoint(
            latitude: (distanceMeters / 6_371_000) * 180 / .pi,
            longitude: 0,
            altitudeMeters: nil,
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracy: 5
        )
    }
}
