import Foundation

enum StravaUploadPlanner {
    static func recordForManualRetry(
        workout: WorkoutSummary,
        existing: StravaUploadRecord?,
        now: Date = Date()
    ) -> StravaUploadRecord? {
        guard workout.source == .healthKit else { return nil }
        guard let existing else {
            return freshPendingRecord(for: workout.id, now: now)
        }

        switch existing.status {
        case .uploading, .processing:
            guard let uploadID = existing.stravaUploadID else {
                return freshPendingRecord(for: workout.id, now: now)
            }
            return StravaUploadRecord(workoutID: workout.id, status: .processing, stravaUploadID: uploadID, updatedAt: now)
        case .uploaded:
            return nil
        case .notUploaded, .pending, .failed:
            return freshPendingRecord(for: workout.id, now: now)
        }
    }

    static func recordAfterSavingLocalEdit(
        workout: WorkoutSummary,
        autoUploadEnabled: Bool,
        existing: StravaUploadRecord?,
        now: Date = Date()
    ) -> StravaUploadRecord? {
        guard autoUploadEnabled, workout.source == .healthKit else { return nil }
        guard let existing else {
            return freshPendingRecord(for: workout.id, now: now)
        }

        switch existing.status {
        case .notUploaded, .pending, .failed:
            return freshPendingRecord(for: workout.id, now: now)
        case .uploading, .processing, .uploaded:
            return nil
        }
    }

    static func uploadIDToPoll(for record: StravaUploadRecord) -> String? {
        switch record.status {
        case .uploading, .processing:
            return record.stravaUploadID
        case .notUploaded, .pending, .uploaded, .failed:
            return nil
        }
    }

    private static func freshPendingRecord(for workoutID: UUID, now: Date) -> StravaUploadRecord {
        StravaUploadRecord(workoutID: workoutID, status: .pending, updatedAt: now)
    }
}
