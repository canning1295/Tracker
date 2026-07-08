import Foundation

struct WorkoutExporter {
    var maximumHeartRateMatchInterval: TimeInterval = 15

    func tcxData(for workout: WorkoutSummary) -> Data {
        let points = trackpoints(for: workout)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="\(sport(for: workout.activity))">
              <Id>\(iso(workout.startDate))</Id>
              <Lap StartTime="\(iso(workout.startDate))">
                <TotalTimeSeconds>\(Int(max(0, workout.duration)))</TotalTimeSeconds>
                <DistanceMeters>\(max(0, workout.distanceMeters))</DistanceMeters>
                <Calories>\(Int(max(0, workout.activeEnergyKilocalories)))</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>\(points)</Track>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """
        return Data(xml.utf8)
    }

    private func trackpoints(for workout: WorkoutSummary) -> String {
        if !workout.route.isEmpty {
            return routeTrackpoints(route: workout.route, heartRateSamples: workout.heartRateSamples)
        }

        return workout.heartRateSamples.map { sample in
            """
            <Trackpoint><Time>\(iso(sample.timestamp))</Time>\(heartRateXML(sample.beatsPerMinute))</Trackpoint>
            """
        }.joined()
    }

    private func routeTrackpoints(route: [RoutePoint], heartRateSamples: [HeartRateSample]) -> String {
        var cumulativeDistance = 0.0
        var previousPoint: RoutePoint?

        return route.map { point in
            if let previousPoint {
                cumulativeDistance += PaceCalculator.distanceMeters(between: previousPoint, and: point)
            }
            previousPoint = point

            let heartRate = nearestHeartRate(to: point.timestamp, samples: heartRateSamples)
            return """
            <Trackpoint><Time>\(iso(point.timestamp))</Time><Position><LatitudeDegrees>\(point.latitude)</LatitudeDegrees><LongitudeDegrees>\(point.longitude)</LongitudeDegrees></Position>\(altitudeXML(point.altitudeMeters))<DistanceMeters>\(cumulativeDistance)</DistanceMeters>\(heartRateXML(heartRate))</Trackpoint>
            """
        }.joined()
    }

    private func nearestHeartRate(to timestamp: Date, samples: [HeartRateSample]) -> Int? {
        guard let nearest = samples.min(by: { first, second in
            abs(first.timestamp.timeIntervalSince(timestamp)) < abs(second.timestamp.timeIntervalSince(timestamp))
        }) else {
            return nil
        }

        guard abs(nearest.timestamp.timeIntervalSince(timestamp)) <= maximumHeartRateMatchInterval else {
            return nil
        }
        return nearest.beatsPerMinute
    }

    private func altitudeXML(_ value: Double?) -> String {
        guard let value else { return "" }
        return "<AltitudeMeters>\(value)</AltitudeMeters>"
    }

    private func heartRateXML(_ value: Int?) -> String {
        guard let value else { return "" }
        return "<HeartRateBpm><Value>\(value)</Value></HeartRateBpm>"
    }

    private func sport(for activity: WorkoutActivity) -> String {
        switch activity {
        case .outdoorBike, .indoorBike: return "Biking"
        case .outdoorRun, .indoorRun: return "Running"
        default: return "Other"
        }
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
