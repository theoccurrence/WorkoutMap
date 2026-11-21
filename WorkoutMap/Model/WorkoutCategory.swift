import UIKit
import HealthKit

enum WorkoutCategory: String, CaseIterable, Identifiable, Hashable {
    case walk, run, ride

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .ride: return "Ride"
        }
    }

    var symbolName: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .ride: return "figure.outdoor.cycle"
        }
    }

    /// The colour the mode shipped with — yellow, orange, green. The user can change it in
    /// Settings; `CategoryColorStore` is what the views read.
    var defaultUIColor: UIColor {
        switch self {
        case .walk: return UIColor(red: 1.0, green: 199.0 / 255.0, blue: 3.0 / 255.0, alpha: 1)
        case .run: return UIColor(red: 235.0 / 255.0, green: 125.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
        case .ride: return UIColor(red: 11.0 / 255.0, green: 169.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .walk: return .walking
        case .run: return .running
        case .ride: return .cycling
        }
    }

    static func from(_ type: HKWorkoutActivityType) -> WorkoutCategory? {
        switch type {
        case .walking: return .walk
        case .running: return .run
        case .cycling: return .ride
        default: return nil
        }
    }

    static var allActivityTypes: [HKWorkoutActivityType] {
        WorkoutCategory.allCases.map(\.activityType)
    }
}
