import Foundation
import CoreLocation

/// Which kind of route the explorer plans.
enum PlanMode: String, CaseIterable, Identifiable {
    /// A loop that starts and ends at the current position.
    case loop
    /// A route from the current position to a destination.
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loop: return "Loop"
        case .destination: return "To a destination"
        }
    }
}

/// What the user asked the planner for.
struct PlanRequest {
    var mode: PlanMode
    /// The distance the user wants to walk, in metres.
    var targetMeters: Double
    /// The destination of a `destination` plan. Unused by `loop`.
    var destination: CLLocationCoordinate2D?
    /// What the destination is called, for the result card.
    var destinationName: String?
}

extension PlanRequest: Equatable {
    static func == (lhs: PlanRequest, rhs: PlanRequest) -> Bool {
        lhs.mode == rhs.mode
            && lhs.targetMeters == rhs.targetMeters
            && lhs.destinationName == rhs.destinationName
            && lhs.destination?.latitude == rhs.destination?.latitude
            && lhs.destination?.longitude == rhs.destination?.longitude
    }
}

/// A destination the user picked: either a search result or the pin they dropped on the map.
struct PlanDestination {
    var coordinate: CLLocationCoordinate2D
    var name: String
    /// True when this is the pin on the map rather than a search result.
    var isPin: Bool
}

extension PlanDestination: Equatable {
    static func == (lhs: PlanDestination, rhs: PlanDestination) -> Bool {
        lhs.isPin == rhs.isPin
            && lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// One planned route: the polyline, how far it goes, and how much of it is new ground.
struct PlannedRoute: Identifiable {
    /// 0 is the primary route, 1 and 2 the alternates.
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let distance: Double
    let travelTime: TimeInterval
    /// Metres of the route that lie on ground no workout has covered yet.
    let uncoveredMeters: Double

    /// The share of the route that is new ground, 0...1.
    var newFraction: Double { distance > 0 ? min(1, uncoveredMeters / distance) : 0 }
}

extension PlannedRoute: Equatable {
    static func == (lhs: PlannedRoute, rhs: PlannedRoute) -> Bool { lhs.id == rhs.id }
}

/// A planned route and its alternates, primary first.
struct RoutePlan {
    let request: PlanRequest
    let start: CLLocationCoordinate2D
    let routes: [PlannedRoute]

    var primary: PlannedRoute? { routes.first }
}
