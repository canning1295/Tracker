import Foundation

#if canImport(HealthKit)
import HealthKit

extension WorkoutActivity {
    static func fromHealthKit(activityType: HKWorkoutActivityType, isIndoor: Bool) -> WorkoutActivity? {
        switch activityType {
        case .running:
            return isIndoor ? .indoorRun : .outdoorRun
        case .walking, .hiking:
            return isIndoor ? .indoorWalk : .outdoorWalk
        case .cycling:
            return isIndoor ? .indoorBike : .outdoorBike
        case .elliptical:
            return .indoorElliptical
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .weights
        default:
            return nil
        }
    }
}
#endif
