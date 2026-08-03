import Foundation
import Observation

enum DeviceReadinessLevel: String, Equatable {
    case ready
    case warning
    case blocked
}

struct DeviceReadinessItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var level: DeviceReadinessLevel
}

@MainActor
@Observable
final class AppState {
    var settings: WorkoutSettings {
        didSet {
            summaryRevision += 1
            settingsStore.saveSettings(settings)
            connectivity.send(settings: settings, intervals: intervals)
        }
    }

    var intervals: [IntervalWorkout] {
        didSet {
            settingsStore.saveIntervals(intervals)
            connectivity.send(settings: settings, intervals: intervals)
        }
    }

    var workouts: [WorkoutSummary] = [] {
        didSet {
            summaryRevision += 1
        }
    }
    var activityEdits: [ActivityEdit] {
        didSet {
            summaryRevision += 1
            settingsStore.saveActivityEdits(activityEdits)
        }
    }
    private(set) var excludedBestEffortWorkoutIDs: Set<UUID> {
        didSet {
            summaryRevision += 1
            settingsStore.saveExcludedBestEffortWorkoutIDs(excludedBestEffortWorkoutIDs)
        }
    }
    private(set) var bestEffortCache: BestEffortCache {
        didSet {
            settingsStore.saveBestEffortCache(bestEffortCache)
        }
    }
    private(set) var bestEffortReviewWorkouts: [UUID: WorkoutSummary] = [:]
    private(set) var bestEffortDetailLoadingIDs: Set<UUID> = []
    private(set) var bestEffortDetailErrors: [UUID: String] = [:]
    private(set) var isLoadingAllTimeBestEfforts = false
    private(set) var bestEffortProcessedCount = 0
    private(set) var bestEffortCandidateCount = 0
    private(set) var bestEffortRefreshRevision = 0
    private(set) var bestEffortLoadingError: String?
    var stravaUploads: [StravaUploadRecord] {
        didSet {
            settingsStore.saveStravaUploads(stravaUploads)
        }
    }
    var authorizationMessage: String?
    var isLoadingWorkouts = false
    private(set) var summaryRevision = 0
    var healthMetricsMessage: String?
    var stravaClientID: String
    var stravaClientSecret: String
    var stravaConnectionMessage: String?
    var stravaIsConnected: Bool
    var stravaRequiredRedirectURI: String {
        StravaClient.redirectURI
    }
    var stravaRequiredCallbackDomain: String {
        URL(string: StravaClient.redirectURI)?.host() ?? "localhost"
    }
    var stravaRequiredScopeText: String {
        StravaClient.requiredScopes.sorted().joined(separator: ", ")
    }
    var stravaHasAnyCredentialInput: Bool {
        !stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var stravaCredentialsAreComplete: Bool {
        !stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var stravaSetupWarnings: [String] {
        var warnings: [String] = []
        let trimmedClientID = stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientSecret = stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedClientID.isEmpty {
            warnings.append("Enter your Strava API Client ID.")
        } else if Int(trimmedClientID) == nil {
            warnings.append("Strava API Client ID should be numeric.")
        }

        if trimmedClientSecret.isEmpty {
            warnings.append("Enter your Strava API Client Secret.")
        }

        if stravaIsConnected {
            let missingScopes = strava.missingRequiredScopes()
            if !missingScopes.isEmpty {
                warnings.append("Reconnect Strava and approve: \(missingScopes.sorted().joined(separator: ", ")).")
            }
        }

        return warnings
    }
    var deviceReadinessItems: [DeviceReadinessItem] {
        [
            appTargetReadiness,
            healthReadiness,
            watchReadiness,
            actionButtonReadiness,
            workoutControlsReadiness,
            watchLocationReadiness,
            stravaReadiness
        ]
    }

    let healthKit = HealthKitClient()
    let strava = StravaClient()
    let connectivity = PhoneConnectivityClient()

    private let settingsStore = SettingsStore()
    private var settingsObserver: NSObjectProtocol?
    private var healthRefreshGeneration = 0
    private var healthDetailLoadTask: Task<Void, Never>?
    private var healthDetailLoadingIDs = Set<UUID>()
    private var watchWorkoutRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var deletedWorkoutIDs: Set<UUID> = [] {
        didSet {
            settingsStore.saveDeletedWorkoutIDs(deletedWorkoutIDs)
        }
    }

    init() {
        self.settings = settingsStore.loadSettings()
        self.intervals = settingsStore.loadIntervals()
        self.activityEdits = settingsStore.loadActivityEdits()
        self.excludedBestEffortWorkoutIDs = settingsStore.loadExcludedBestEffortWorkoutIDs()
        self.bestEffortCache = settingsStore.loadBestEffortCache()
        self.stravaUploads = settingsStore.loadStravaUploads()
        self.deletedWorkoutIDs = settingsStore.loadDeletedWorkoutIDs()
        let credentials = strava.storedCredentials()
        self.stravaClientID = credentials.clientID
        self.stravaClientSecret = credentials.clientSecret
        self.stravaIsConnected = strava.hasStoredToken()
        connectivity.onWorkoutFinished = { [weak self] completion in
            Task { @MainActor in
                self?.handleWatchWorkoutFinished(completion)
            }
        }
        connectivity.onSettingsReceived = { [weak self] settings in
            Task { @MainActor in
                self?.settings = settings
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: TrackerSettingsChange.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let settings = TrackerSettingsChange.settings(from: notification) else { return }
            Task { @MainActor in
                guard self?.settings != settings else { return }
                self?.settings = settings
            }
        }
        connectivity.activate()
        connectivity.send(settings: settings, intervals: intervals)
    }

    func refreshHealthData() async {
        guard !isLoadingWorkouts else { return }
        healthRefreshGeneration += 1
        let generation = healthRefreshGeneration
        healthDetailLoadTask?.cancel()
        isLoadingWorkouts = true

        do {
            try await healthKit.requestAuthorization()
            let healthWorkouts = try await healthKit.loadRecentWorkouts(limit: 50, includesDetails: false, userMetrics: settings.userMetrics)
            guard generation == healthRefreshGeneration else { return }
            let visibleHealthWorkouts = healthWorkouts.filter { !deletedWorkoutIDs.contains($0.id) }
            workouts = mergedWithExistingDetails(visibleHealthWorkouts)
            bestEffortRefreshRevision += 1
            healthDetailLoadingIDs = Set(visibleHealthWorkouts.map(\.id))
            authorizationMessage = healthWorkouts.isEmpty ? "No supported Apple Health workouts were found." : nil
            isLoadingWorkouts = false
            healthDetailLoadTask = Task { [weak self] in
                await self?.loadHealthDetails(for: visibleHealthWorkouts, generation: generation)
            }
        } catch {
            guard generation == healthRefreshGeneration else { return }
            healthDetailLoadingIDs = []
            isLoadingWorkouts = false
            authorizationMessage = error.localizedDescription
        }
    }

    func addInterval(_ workout: IntervalWorkout) {
        intervals.append(workout)
    }

    func saveInterval(_ workout: IntervalWorkout) {
        if let index = intervals.firstIndex(where: { $0.id == workout.id }) {
            intervals[index] = workout
        } else {
            intervals.append(workout)
        }
    }

    func deleteIntervals(at offsets: IndexSet) {
        intervals.remove(atOffsets: offsets)
    }

    func moveOutdoor(from source: IndexSet, to destination: Int) {
        settings.outdoorOrder.move(fromOffsets: source, toOffset: destination)
    }

    func moveIndoor(from source: IndexSet, to destination: Int) {
        settings.indoorOrder.move(fromOffsets: source, toOffset: destination)
    }

    func importUserMetricsFromHealth() async {
        do {
            try await healthKit.requestAuthorization()
            let healthMetrics = try await healthKit.loadUserMetrics()
            let imported = applyHealthMetrics(healthMetrics, overwrite: true)
            if imported.isEmpty {
                healthMetricsMessage = "No age, sex, height, weight, resting HR, or VO2 values were available in Apple Health."
            } else {
                healthMetricsMessage = "Imported \(imported.joined(separator: ", ")) from Apple Health."
            }
        } catch {
            healthMetricsMessage = error.localizedDescription
        }
    }

    func startOnWatch(activity: WorkoutActivity) {
        connectivity.sendStart(activity: activity)
    }

    func consumePendingIntentStart() {
        guard let activity = PendingWorkoutStartStore.consume() else { return }
        startOnWatch(activity: activity)
    }

    func edit(for workoutID: UUID) -> ActivityEdit {
        activityEdits.first { $0.workoutID == workoutID } ?? ActivityEdit(workoutID: workoutID)
    }

    func adjustedWorkout(_ workout: WorkoutSummary) -> WorkoutSummary {
        WorkoutEditApplier.adjustedWorkout(workout, edit: edit(for: workout.id))
    }

    func latestWorkout(for id: UUID) -> WorkoutSummary? {
        workouts.first { $0.id == id }
    }

    func isLoadingDetails(for workoutID: UUID) -> Bool {
        healthDetailLoadingIDs.contains(workoutID)
    }

    var bestEffortResults: [BestEffortDistance: BestEffortResult] {
        bestEffortCache.fastestEfforts(excluding: excludedBestEffortWorkoutIDs)
    }

    func bestEffortWorkout(for workoutID: UUID) -> WorkoutSummary? {
        if let reviewedWorkout = bestEffortReviewWorkouts[workoutID] {
            return reviewedWorkout
        }
        guard let recentWorkout = latestWorkout(for: workoutID), !recentWorkout.route.isEmpty else {
            return nil
        }
        return recentWorkout
    }

    func bestEffortDetailError(for workoutID: UUID) -> String? {
        bestEffortDetailErrors[workoutID]
    }

    func loadBestEffortWorkout(_ workoutID: UUID) async {
        guard bestEffortWorkout(for: workoutID) == nil,
              !bestEffortDetailLoadingIDs.contains(workoutID) else {
            return
        }

        bestEffortDetailErrors.removeValue(forKey: workoutID)
        bestEffortDetailLoadingIDs.insert(workoutID)
        defer { bestEffortDetailLoadingIDs.remove(workoutID) }

        do {
            let workout = try await healthKit.loadWorkout(id: workoutID, userMetrics: settings.userMetrics)
            guard !deletedWorkoutIDs.contains(workoutID) else { return }
            bestEffortReviewWorkouts[workoutID] = workout
        } catch {
            bestEffortDetailErrors[workoutID] = error.localizedDescription
        }
    }

    func refreshAllTimeBestEfforts() async {
        guard !isLoadingAllTimeBestEfforts else { return }
        isLoadingAllTimeBestEfforts = true
        bestEffortProcessedCount = 0
        bestEffortCandidateCount = 0
        bestEffortLoadingError = nil
        defer {
            isLoadingAllTimeBestEfforts = false
        }

        do {
            try await healthKit.requestAuthorization()
            let allRuns = try await healthKit.loadAllOutdoorRuns(userMetrics: settings.userMetrics)
                .filter { !deletedWorkoutIDs.contains($0.id) }
            let allRunIDs = Set(allRuns.map(\.id))
            var retainedCache = bestEffortCache
            if !allRunIDs.isEmpty {
                retainedCache.retain(workoutIDs: allRunIDs)
            }
            if retainedCache != bestEffortCache {
                bestEffortCache = retainedCache
            }

            let evaluatedIDs = Set(bestEffortCache.entries.map(\.workoutID))
            let candidates = allRuns.filter { !evaluatedIDs.contains($0.id) }
            bestEffortCandidateCount = candidates.count

            for workout in candidates {
                guard !Task.isCancelled else { return }
                guard let routeData = try? await healthKit.loadWorkoutRouteData(for: workout) else {
                    bestEffortProcessedCount += 1
                    continue
                }
                var routedWorkout = workout
                routedWorkout.route = routeData.route
                routedWorkout.recordedPauseRanges = routeData.recordedPauseRanges
                await cacheBestEfforts(for: routedWorkout)
                bestEffortProcessedCount += 1
            }

            guard !Task.isCancelled else { return }
            await loadBestEffortReviewWorkouts(from: allRuns)
        } catch {
            bestEffortLoadingError = error.localizedDescription
        }
    }

    var adjustedWorkouts: [WorkoutSummary] {
        workouts.map(adjustedWorkout)
    }

    func saveEdit(_ edit: ActivityEdit) {
        let workout = workouts.first { $0.id == edit.workoutID }

        guard edit.hasAdjustments else {
            activityEdits.removeAll { $0.workoutID == edit.workoutID }
            invalidateBestEffortCache(for: edit.workoutID, activity: workout?.activity)
            refreshStravaQueueAfterLocalEdit(for: workout)
            return
        }

        if let index = activityEdits.firstIndex(where: { $0.workoutID == edit.workoutID }) {
            activityEdits[index] = edit
        } else {
            activityEdits.append(edit)
        }
        invalidateBestEffortCache(for: edit.workoutID, activity: workout?.activity)
        refreshStravaQueueAfterLocalEdit(for: workout)
    }

    func isIncludedInBestEfforts(_ workoutID: UUID) -> Bool {
        !excludedBestEffortWorkoutIDs.contains(workoutID)
    }

    func setBestEffortInclusion(_ included: Bool, for workoutID: UUID) {
        var updated = excludedBestEffortWorkoutIDs
        if included {
            updated.remove(workoutID)
        } else {
            updated.insert(workoutID)
        }
        guard updated != excludedBestEffortWorkoutIDs else { return }
        excludedBestEffortWorkoutIDs = updated
        bestEffortRefreshRevision += 1
    }

    func deleteWorkout(_ workout: WorkoutSummary) async -> Bool {
        deletedWorkoutIDs.insert(workout.id)
        healthDetailLoadingIDs.remove(workout.id)
        workouts.removeAll { $0.id == workout.id }
        activityEdits.removeAll { $0.workoutID == workout.id }
        invalidateBestEffortCache(for: workout.id, activity: workout.activity)
        setBestEffortInclusion(true, for: workout.id)
        stravaUploads.removeAll { $0.workoutID == workout.id }

        guard workout.source == .healthKit else {
            authorizationMessage = nil
            return true
        }

        do {
            try await healthKit.requestAuthorization()
            do {
                try await healthKit.deleteWorkout(id: workout.id)
                authorizationMessage = nil
            } catch {
                authorizationMessage = "Removed from Tracker. Apple Health did not delete it: \(error.localizedDescription)"
            }
        } catch {
            authorizationMessage = "Removed from Tracker. Apple Health was not updated: \(error.localizedDescription)"
        }

        return true
    }

    func stravaStatus(for workoutID: UUID) -> StravaUploadStatus {
        stravaUploads.first { $0.workoutID == workoutID }?.status ?? .notUploaded
    }

    func stravaRecord(for workoutID: UUID) -> StravaUploadRecord? {
        stravaUploads.first { $0.workoutID == workoutID }
    }

    func retryStravaUpload(workout: WorkoutSummary) {
        guard workout.source == .healthKit else {
            stravaConnectionMessage = "Only Apple Health workouts are uploaded to Strava."
            return
        }
        let existing = stravaRecord(for: workout.id)
        guard let retryRecord = StravaUploadPlanner.recordForManualRetry(workout: workout, existing: existing) else {
            stravaConnectionMessage = "This workout is already uploaded to Strava. Delete it in Strava before uploading a new edited copy."
            return
        }
        upsertStravaRecord(retryRecord)
        Task { await processStravaQueue(requiresAutoUpload: false) }
    }

    func saveStravaCredentials() {
        do {
            try strava.saveCredentials(clientID: stravaClientID, clientSecret: stravaClientSecret)
            stravaConnectionMessage = "Strava credentials saved."
        } catch {
            stravaConnectionMessage = error.localizedDescription
        }
    }

    func requestStravaCredentialSetup() {
        stravaConnectionMessage = "Create or open your Strava API application, copy its Client ID and Client Secret here, then connect again."
    }

    func connectStrava(forceLogin: Bool = false) async {
        do {
            try strava.saveCredentials(clientID: stravaClientID, clientSecret: stravaClientSecret)
            let result = try await strava.authorize(forceLogin: forceLogin)
            switch result {
            case .connected:
                stravaIsConnected = true
                stravaConnectionMessage = "Strava connected."
                await processStravaQueue()
            case .openedStravaApp:
                stravaConnectionMessage = "Approve Tracker in Strava, then return here."
            }
        } catch {
            stravaIsConnected = strava.hasStoredToken()
            stravaConnectionMessage = error.localizedDescription
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard url.scheme == "tracker" else { return }
        do {
            try await strava.handleCallback(url: url)
            stravaIsConnected = true
            stravaConnectionMessage = "Strava connected."
            await processStravaQueue()
        } catch {
            stravaConnectionMessage = error.localizedDescription
        }
    }

    func disconnectStrava() {
        strava.disconnect()
        stravaIsConnected = false
        stravaConnectionMessage = "Strava disconnected."
    }

    func handleWatchWorkoutFinished(_ completion: WatchWorkoutCompletion) {
        guard watchWorkoutRefreshTasks[completion.workoutID] == nil else { return }

        watchWorkoutRefreshTasks[completion.workoutID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.watchWorkoutRefreshTasks[completion.workoutID] = nil }

            await self.refreshHealthData()
            for retryDelay in [2, 5, 10] {
                guard !self.workouts.contains(where: { $0.id == completion.workoutID }) else { return }
                do {
                    try await Task.sleep(for: .seconds(retryDelay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshHealthData()
            }
        }
    }

    private func enqueueAutoUploadsIfNeeded() {
        guard settings.stravaAutoUpload else { return }
        for workout in workouts where workout.source == .healthKit && stravaRecord(for: workout.id) == nil {
            upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .pending))
        }
    }

    private func processStravaQueue(requiresAutoUpload: Bool = true) async {
        guard !requiresAutoUpload || settings.stravaAutoUpload else { return }
        let token: String
        do {
            guard let resolvedToken = try await strava.validAccessToken() else { return }
            token = resolvedToken
        } catch {
            stravaConnectionMessage = error.localizedDescription
            return
        }

        let pending = stravaUploads.filter { $0.status == .pending || $0.status == .failed || $0.status == .uploading || $0.status == .processing }
        for record in pending {
            guard let workout = workouts.first(where: { $0.id == record.workoutID }) else { continue }
            guard workout.source == .healthKit else {
                upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .failed, lastError: "Only Apple Health workouts are uploaded to Strava."))
                continue
            }
            var knownUploadID = StravaUploadPlanner.uploadIDToPoll(for: record)
            guard knownUploadID != nil || !healthDetailLoadingIDs.contains(workout.id) else {
                continue
            }
            do {
                let uploadResult: StravaUploadResult

                if let uploadID = knownUploadID {
                    upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .processing, stravaUploadID: uploadID))
                    uploadResult = try await strava.waitForUploadProcessing(uploadID: uploadID, accessToken: token)
                } else {
                    upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .uploading))
                    let exportWorkout = adjustedWorkout(workout)
                    let export = WorkoutExporter().tcxData(for: exportWorkout)
                    let createdUpload = try await strava.createUpload(workout: exportWorkout, tcxData: export, accessToken: token)
                    knownUploadID = createdUpload.uploadID
                    upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .processing, stravaUploadID: createdUpload.uploadID))

                    if createdUpload.activityID == nil {
                        uploadResult = try await strava.waitForUploadProcessing(uploadID: createdUpload.uploadID, accessToken: token)
                    } else {
                        uploadResult = createdUpload
                    }
                }

                guard let activityID = uploadResult.activityID else {
                    throw StravaClientError.uploadTimedOut(uploadResult.uploadID)
                }
                upsertStravaRecord(StravaUploadRecord(workoutID: workout.id, status: .uploaded, stravaUploadID: uploadResult.uploadID, stravaActivityID: activityID))
            } catch StravaClientError.uploadTimedOut(let uploadID) {
                upsertStravaRecord(StravaUploadRecord(
                    workoutID: workout.id,
                    status: .processing,
                    stravaUploadID: uploadID,
                    lastError: StravaClientError.uploadTimedOut(uploadID).localizedDescription
                ))
            } catch {
                upsertStravaRecord(StravaUploadRecord(
                    workoutID: workout.id,
                    status: .failed,
                    stravaUploadID: knownUploadID,
                    lastError: error.localizedDescription
                ))
            }
        }
    }

    private func refreshStravaQueueAfterLocalEdit(for workout: WorkoutSummary?) {
        guard let workout else { return }
        let existing = stravaRecord(for: workout.id)
        guard let record = StravaUploadPlanner.recordAfterSavingLocalEdit(
            workout: workout,
            autoUploadEnabled: settings.stravaAutoUpload,
            existing: existing
        ) else {
            return
        }
        upsertStravaRecord(record)
        Task { await processStravaQueue() }
    }

    private func upsertStravaRecord(_ record: StravaUploadRecord) {
        if let index = stravaUploads.firstIndex(where: { $0.workoutID == record.workoutID }) {
            stravaUploads[index] = record
        } else {
            stravaUploads.append(record)
        }
    }

    private func loadHealthDetails(for metadataWorkouts: [WorkoutSummary], generation: Int) async {
        if let healthMetrics = try? await healthKit.loadUserMetrics(), generation == healthRefreshGeneration {
            _ = applyHealthMetrics(healthMetrics, overwrite: false)
        }

        for workout in metadataWorkouts {
            guard !Task.isCancelled, generation == healthRefreshGeneration else { return }
            guard !deletedWorkoutIDs.contains(workout.id) else {
                healthDetailLoadingIDs.remove(workout.id)
                continue
            }
            guard let detailedWorkout = try? await healthKit.loadWorkoutDetails(for: workout, userMetrics: settings.userMetrics) else {
                healthDetailLoadingIDs.remove(workout.id)
                continue
            }
            guard !Task.isCancelled, generation == healthRefreshGeneration else { return }
            guard !deletedWorkoutIDs.contains(detailedWorkout.id) else {
                healthDetailLoadingIDs.remove(detailedWorkout.id)
                continue
            }
            upsertWorkout(detailedWorkout)
            await cacheBestEfforts(for: detailedWorkout)
            healthDetailLoadingIDs.remove(workout.id)
        }

        guard !Task.isCancelled, generation == healthRefreshGeneration else { return }
        enqueueAutoUploadsIfNeeded()
        await processStravaQueue()
    }

    private func upsertWorkout(_ workout: WorkoutSummary) {
        guard !deletedWorkoutIDs.contains(workout.id) else { return }
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
        } else {
            workouts.append(workout)
            workouts.sort { $0.startDate > $1.startDate }
        }
    }

    private func cacheBestEfforts(for workout: WorkoutSummary) async {
        guard workout.activity == .outdoorRun, !bestEffortCache.hasEvaluated(workout.id) else { return }
        if workout.distanceMeters >= BestEffortDistance.meters100.meters {
            guard workout.route.count >= 2 else { return }
        }
        let adjustedWorkout = adjustedWorkout(workout)
        let efforts = await Task.detached(priority: .utility) {
            BestEffortEngine.fastestEfforts(workouts: [adjustedWorkout])
        }.value
        guard !Task.isCancelled else { return }
        var updatedCache = bestEffortCache
        updatedCache.store(
            workoutID: workout.id,
            workoutStartDate: workout.startDate,
            efforts: efforts
        )
        bestEffortCache = updatedCache
    }

    private func loadBestEffortReviewWorkouts(from metadataWorkouts: [WorkoutSummary]) async {
        let recordIDs = Set(bestEffortResults.values.map(\.workoutID))
        bestEffortReviewWorkouts = bestEffortReviewWorkouts.filter { recordIDs.contains($0.key) }
        let metadataByID = Dictionary(uniqueKeysWithValues: metadataWorkouts.map { ($0.id, $0) })

        for workoutID in recordIDs where bestEffortReviewWorkouts[workoutID] == nil {
            guard !Task.isCancelled else { return }
            if let recentWorkout = latestWorkout(for: workoutID), !recentWorkout.route.isEmpty {
                bestEffortReviewWorkouts[workoutID] = recentWorkout
                continue
            }
            guard let metadata = metadataByID[workoutID],
                  let detailedWorkout = try? await healthKit.loadWorkoutDetails(for: metadata, userMetrics: settings.userMetrics) else {
                continue
            }
            bestEffortReviewWorkouts[workoutID] = detailedWorkout
        }
    }

    private func invalidateBestEffortCache(for workoutID: UUID, activity: WorkoutActivity?) {
        guard activity == .outdoorRun || bestEffortCache.hasEvaluated(workoutID) else { return }
        var updatedCache = bestEffortCache
        updatedCache.remove(workoutID)
        if updatedCache != bestEffortCache {
            bestEffortCache = updatedCache
        }
        bestEffortReviewWorkouts.removeValue(forKey: workoutID)
        bestEffortDetailErrors.removeValue(forKey: workoutID)
        bestEffortRefreshRevision += 1
    }

    private func mergedWithExistingDetails(_ metadataWorkouts: [WorkoutSummary]) -> [WorkoutSummary] {
        metadataWorkouts.filter { !deletedWorkoutIDs.contains($0.id) }.map { metadata in
            guard let existing = workouts.first(where: { $0.id == metadata.id }) else {
                return metadata
            }

            return WorkoutSummary(
                id: metadata.id,
                source: metadata.source,
                activity: metadata.activity,
                startDate: metadata.startDate,
                endDate: metadata.endDate,
                duration: metadata.duration,
                distanceMeters: metadata.distanceMeters,
                activeEnergyKilocalories: metadata.activeEnergyKilocalories,
                averageHeartRate: existing.averageHeartRate,
                maxHeartRate: existing.maxHeartRate,
                route: existing.route,
                heartRateSamples: existing.heartRateSamples,
                stravaState: metadata.stravaState
            )
        }
    }

    private var appTargetReadiness: DeviceReadinessItem {
        let bundleID = Bundle.main.bundleIdentifier ?? "Unknown bundle ID"
        if bundleID.hasSuffix(".phoneonly") {
            return DeviceReadinessItem(
                title: "Install Target",
                detail: "Running the simulator-only target. Use the Tracker scheme for signed iPhone + Watch testing.",
                level: .warning
            )
        }

        return DeviceReadinessItem(
            title: "Install Target",
            detail: "Bundle \(bundleID) is the embedded iPhone + Watch app target.",
            level: .ready
        )
    }

    private var healthReadiness: DeviceReadinessItem {
        guard healthKit.isHealthDataAvailable else {
            return DeviceReadinessItem(
                title: "Apple Health",
                detail: "Health data is not available on this device.",
                level: .blocked
            )
        }

        if let authorizationMessage {
            return DeviceReadinessItem(
                title: "Apple Health",
                detail: authorizationMessage,
                level: .warning
            )
        }

        if workouts.isEmpty {
            return DeviceReadinessItem(
                title: "Apple Health",
                detail: "HealthKit is available. No supported workouts are currently loaded.",
                level: .warning
            )
        }

        return DeviceReadinessItem(
            title: "Apple Health",
            detail: "HealthKit is available and real workouts are loaded.",
            level: .ready
        )
    }

    private var watchReadiness: DeviceReadinessItem {
        let readiness = connectivity.readiness()
        let level: DeviceReadinessLevel
        switch readiness.status {
        case .ready: level = .ready
        case .warning: level = .warning
        case .blocked: level = .blocked
        }
        return DeviceReadinessItem(title: "Apple Watch", detail: readiness.message, level: level)
    }

    private var actionButtonReadiness: DeviceReadinessItem {
        DeviceReadinessItem(
            title: "Action Button",
            detail: "Assign the Tracker Open Tracker shortcut to the Apple Watch Ultra Action Button, then run a signed device test.",
            level: .warning
        )
    }

    private var workoutControlsReadiness: DeviceReadinessItem {
        DeviceReadinessItem(
            title: "Workout Controls",
            detail: "Watch on-screen Pause/Resume and End are wired. Physical side-button behavior still needs validation on the installed Watch app.",
            level: .warning
        )
    }

    private var watchLocationReadiness: DeviceReadinessItem {
        DeviceReadinessItem(
            title: "Outdoor Routes",
            detail: "Location permission is requested on the Watch when starting an outdoor workout.",
            level: .warning
        )
    }

    private var stravaReadiness: DeviceReadinessItem {
        let missingScopes = strava.missingRequiredScopes()
        if stravaIsConnected, missingScopes.isEmpty {
            return DeviceReadinessItem(
                title: "Strava",
                detail: "Connected with required upload scope.",
                level: .ready
            )
        }

        if stravaIsConnected, !missingScopes.isEmpty {
            return DeviceReadinessItem(
                title: "Strava",
                detail: "Reconnect and approve: \(missingScopes.sorted().joined(separator: ", ")).",
                level: .blocked
            )
        }

        if stravaSetupWarnings.isEmpty {
            return DeviceReadinessItem(
                title: "Strava",
                detail: "Credentials are present. Connect Strava before verifying auto-upload.",
                level: .warning
            )
        }

        return DeviceReadinessItem(
            title: "Strava",
            detail: stravaSetupWarnings.joined(separator: " "),
            level: .warning
        )
    }

    @discardableResult
    private func applyHealthMetrics(_ healthMetrics: UserMetrics, overwrite: Bool) -> [String] {
        var updated = settings.userMetrics
        var imported: [String] = []

        if let value = healthMetrics.age, overwrite || updated.age == nil {
            updated.age = value
            imported.append("age")
        }

        if let value = healthMetrics.biologicalSex, overwrite || updated.biologicalSex == nil {
            updated.biologicalSex = value
            imported.append("sex")
        }

        if let value = healthMetrics.heightCentimeters, overwrite || updated.heightCentimeters == nil {
            updated.heightCentimeters = value
            imported.append("height")
        }

        if let value = healthMetrics.weightKilograms, overwrite || updated.weightKilograms == nil {
            updated.weightKilograms = value
            imported.append("weight")
        }

        if let value = healthMetrics.restingHeartRate, overwrite || updated.restingHeartRate == nil {
            updated.restingHeartRate = value
            imported.append("resting HR")
        }

        if let value = healthMetrics.knownVO2Max, overwrite || updated.knownVO2Max == nil {
            updated.knownVO2Max = value
            imported.append("VO2 max")
        }

        if updated != settings.userMetrics {
            settings.userMetrics = updated
        }

        return imported
    }
}
