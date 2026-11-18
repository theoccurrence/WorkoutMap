import MapKit
import CoreLocation

enum RouteGeometry {
    /// Fit factor: routes are drawn inside 1/1.8 of the visible dimension, i.e. the
    /// map is zoomed out by 40 % of the content span on every side.
    static let fitFactor: Double = 1.8
    static let minSpanMeters: Double = 400

    static func mapRect(for coordinate: CLLocationCoordinate2D) -> MKMapRect {
        let p = MKMapPoint(coordinate)
        return MKMapRect(x: p.x, y: p.y, width: 0, height: 0)
    }

    static func union(_ routes: [[CLLocationCoordinate2D]]) -> MKMapRect? {
        var rect: MKMapRect?
        for route in routes where !route.isEmpty {
            for c in route {
                let r = mapRect(for: c)
                rect = rect?.union(r) ?? r
            }
        }
        return rect
    }

    static func fitted(_ rect: MKMapRect, factor: Double = fitFactor) -> MKMapRect {
        var r = rect
        let lat = MKMapPoint(x: r.midX, y: r.midY).coordinate.latitude
        let minSpan = MKMapPointsPerMeterAtLatitude(lat) * minSpanMeters
        if r.width < minSpan || r.height < minSpan {
            let w = max(r.width, minSpan)
            let h = max(r.height, minSpan)
            r = MKMapRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        }
        let dx = r.width * (factor - 1) / 2
        let dy = r.height * (factor - 1) / 2
        return r.insetBy(dx: -dx, dy: -dy)
    }

    static func fittedRect(routes: [[CLLocationCoordinate2D]], factor: Double = fitFactor) -> MKMapRect? {
        guard let u = union(routes) else { return nil }
        return fitted(u, factor: factor)
    }
}
