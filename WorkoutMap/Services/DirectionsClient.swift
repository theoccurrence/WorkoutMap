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
#endif
