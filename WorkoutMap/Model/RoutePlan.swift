import Foundation
import CoreLocation
import MapKit

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

/// Which of the explorer's two algorithms plans the route.
///
/// This is a proof of concept: both live side by side so the two can be compared on the same
/// start and the same coverage, and `WM_PLAN_ALGO` picks between them at launch.
enum PlanStrategy: String, CaseIterable, Identifiable {
    /// The shipped zigzag: a handful of long legs, sized so their straight-line length is the
    /// distance asked for.
    case zigzag
    /// The tour: a disc of ground sized so the streets in it are the distance asked for, swept
    /// row by row so the walk takes the new ground rather than passing it.
    case tour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zigzag: return "Zigzag"
        case .tour: return "Coverage tour"
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

/// What the map knows about the pin the user dropped: the address the geocoder resolved for it,
/// and what is there.
struct PinPlace: Equatable {
    var title: String
    var subtitle: String

    /// Reverse-geocodes a coordinate for the pin's info bubble. Falls back to the coordinate
    /// itself, so the bubble always says something.
    static func describe(_ coordinate: CLLocationCoordinate2D) async -> PinPlace {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // `MKReverseGeocodingRequest` rather than `CLGeocoder`, which is deprecated in iOS 26.
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            // What is *at* the pin — the park, the square, the shop — on top, and the address
            // underneath.
            let address = item.address?.fullAddress
            let title = item.name ?? item.address?.shortAddress ?? "Dropped pin"
            // The full address repeats the name it starts with ("Putziger Straße 39A, 81929
            // Munich, Germany"); the bubble does not need it twice.
            var subtitle = address ?? coordinatesText(coordinate)
            if let address, address.hasPrefix(title) {
                let rest = address.dropFirst(title.count)
                    .drop(while: { $0 == "," || $0 == " " })
                subtitle = rest.isEmpty ? address : String(rest)
            }
            return PinPlace(title: title, subtitle: subtitle)
        }
        return PinPlace(title: "Dropped pin", subtitle: coordinatesText(coordinate))
    }

    private static func coordinatesText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
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
