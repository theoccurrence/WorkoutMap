import Foundation
import MapKit
import CoreLocation

/// One leg of a route as the directions service returns it: the polyline to walk, how far it
/// goes and how long it is expected to take.
struct DirectionsLeg {
    let coordinates: [CLLocationCoordinate2D]
    let distance: Double
    let travelTime: TimeInterval
}

enum DirectionsError: Error {
    /// The service has no route between the two points.
    case noRoute
    /// The service asked us to slow down (`MKError.Code.loadingThrottled`).
    case throttled
    case failed
}

/// The routing backend behind the explorer.
///
/// A protocol so the planner can be exercised without a network — against the fixture client
/// (`WM_FAKE_PLAN`) and in the throwaway self test. Apple's own `MKDirections` has no notion
/// of waypoints, so a loop is planned as a handful of point-to-point legs that are stitched
/// together; each call here is exactly one of those legs.
protocol DirectionsClient: Sendable {
    /// Routes from one point to another. The first leg is the primary route, any further ones
    /// are the service's own alternates.
    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D) async throws -> [DirectionsLeg]
}

/// `MKDirections`, walking.
final class MapKitDirectionsClient: DirectionsClient {
    private let transport: MKDirectionsTransportType

    init(transport: MKDirectionsTransportType = .walking) {
        self.transport = transport
    }

    /// A plain coordinate as a map item — `MKPlacemark` is deprecated in iOS 26.
    private static func item(at coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: coordinate.latitude,
                                      longitude: coordinate.longitude),
                  address: nil)
    }

    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D) async throws -> [DirectionsLeg] {
        let request = MKDirections.Request()
        request.source = MapKitDirectionsClient.item(at: from)
        request.destination = MapKitDirectionsClient.item(at: to)
        request.transportType = transport
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            let legs = response.routes.map {
                DirectionsLeg(coordinates: $0.polyline.coordinates,
                              distance: $0.distance,
                              travelTime: $0.expectedTravelTime)
            }
            guard let first = legs.first, first.coordinates.count > 1 else { throw DirectionsError.noRoute }
            return legs
        } catch let error as MKError {
            switch error.code {
            case .loadingThrottled: throw DirectionsError.throttled
            case .directionsNotFound, .placemarkNotFound: throw DirectionsError.noRoute
            default: throw DirectionsError.failed
            }
        }
    }
}

/// Holds a plan's requests to the directions service back to a pace it does not throttle, and
/// slows the whole plan down when it pushes back anyway.
///
/// A plan asks for up to sixty legs, and the service answers a burst with
/// `MKError.Code.loadingThrottled` rather than with a route. A throttle is a judgement on the
/// burst, not on the leg it landed on, so the pacer turns it into a longer wait for every
/// request that follows and eases off again once requests are being answered. One pacer per
/// plan: the legs of a candidate, the candidates themselves and a destination's detour rounds
/// all draw on the same brake, which is what stops the plan from being throttled as a whole.
actor DirectionsPacer {
    /// The spacing the plan settles on while the service is happy, and — with the ceiling — the
    /// two ends of what a throttle moves the spacing between.
    ///
    /// 1.2 s is not a guess: `MKDirections` answers about **fifty requests a minute** and refuses
    /// the rest with `MKError.Code.loadingThrottled`, which is a *budget* rather than a hiccup —
    /// a burst that spends it leaves later requests refused however patiently they are asked
    /// again, because their retries come out of the same budget. Measured against the real
    /// service: 74 requests in 74 s (60 a minute) got seven legs refused again and again, and
    /// every one of those refusals was a throttle. One request every 1.2 s keeps a plan inside
    /// the budget with room for the retries it needs.
    private static let relaxed = Duration.milliseconds(1200)
    /// What a throttle does to the spacing: a plan that is being refused is over the budget, and
    /// waiting seconds rather than milliseconds is the only thing that puts it back inside.
    private static let strained = Duration.seconds(12)
    /// How many requests in a row have to be answered before the plan speeds up again. Four
    /// rather than eight: a plan that has been throttled has to be able to come back up while it
    /// is still working through a long fill, or one bad moment near the start leaves it crawling
    /// for the rest of the plan.
    private static let reliefAfter = 4

    private let base: Duration
    private var spacing: Duration
    private var nextStart = ContinuousClock.now
    private var answered = 0

    init(spacing: Duration = DirectionsPacer.relaxed) {
        self.base = spacing
        self.spacing = spacing
    }

    /// Waits for this request's turn and reserves the slot after it. Callers are the plan's own
    /// legs, so the wait is the point rather than a cost.
    func acquire() async {
        let now = ContinuousClock.now
        let slot = max(now, nextStart)
        nextStart = slot + spacing
        guard slot > now else { return }
        try? await ContinuousClock().sleep(until: slot, tolerance: .milliseconds(20))
    }

    /// The service asked the plan to slow down: the request that follows waits longer, and so
    /// does every one after it until routes are coming back again.
    func throttled() {
        answered = 0
        spacing = min(Self.strained, spacing * 2)
        nextStart = max(nextStart, ContinuousClock.now + spacing)
    }

    /// A request came back with a route in it.
    func succeeded() {
        answered += 1
        guard answered >= Self.reliefAfter else { return }
        answered = 0
        spacing = max(base, spacing / 2)
    }

    /// A pause before a pass that follows a burst — the rest of the plan has just been through
    /// the service, and a leg it refused a moment ago usually answers now.
    func cool() {
        nextStart = max(nextStart, ContinuousClock.now + max(spacing, .milliseconds(750)))
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                   count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

#if DEBUG
/// A stand-in for `MKDirections` that needs no network: it bows the straight line between the
/// two points into an arc, so a planned route is visibly a route and the planner's UI can be
/// exercised offline (`WM_FAKE_PLAN=1`).
struct FixtureDirectionsClient: DirectionsClient {
    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D) async throws -> [DirectionsLeg] {
        try? await Task.sleep(for: .milliseconds(120))
        let direct = CoverageIndex.meters(from: from, to: to)
        guard direct > 1 else { throw DirectionsError.noRoute }
        let bow = direct * 0.12
        let steps = max(8, min(120, Int(direct / 20)))
        var coordinates: [CLLocationCoordinate2D] = []
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            let point = CoverageIndex.interpolate(from, to, t)
            let side = sin(t * .pi) * bow
            coordinates.append(Geo.offset(point, east: side, north: side * 0.5))
        }
        return [DirectionsLeg(coordinates: coordinates,
                              distance: CoverageIndex.length(of: coordinates),
                              travelTime: direct / 1.35)]
    }
}

/// The service on a bad day: every leg is refused, which is what a plan the planner cannot
/// finish looks like from its side (`WM_PLAN_DEAD=1`). The screen's own empty-handed state is
/// otherwise only reachable by waiting for the routing service to have a bad day — and the
/// explorer's answer to it is the one thing worth looking at before that happens.
struct RefusingDirectionsClient: DirectionsClient {
    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D) async throws -> [DirectionsLeg] {
        throw DirectionsError.noRoute
    }
}
#endif
