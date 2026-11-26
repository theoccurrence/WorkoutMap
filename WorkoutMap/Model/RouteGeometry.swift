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

/// Local plane geometry for the explorer: offsets, bearings and positions along a polyline.
///
/// `MKMapPoint` is Web Mercator, which is conformal — the local scale is the same in every
/// direction — so `MKMapPointsPerMeterAtLatitude` converts a metre offset into map points in
/// both axes, and a few-hundred-metre offset stays faithful.
enum Geo {
    /// `coordinate` moved `east` metres east and `north` metres north.
    static func offset(_ coordinate: CLLocationCoordinate2D,
                       east: Double,
                       north: Double) -> CLLocationCoordinate2D {
        let point = MKMapPoint(coordinate)
        let perMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        return MKMapPoint(x: point.x + east * perMeter,
                          y: point.y - north * perMeter).coordinate
    }

    /// The point `distance` metres from `coordinate` along the given bearing (degrees from
    /// true north).
    static func destination(from coordinate: CLLocationCoordinate2D,
                            bearing: Double,
                            distance: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        return offset(coordinate, east: sin(radians) * distance, north: cos(radians) * distance)
    }

    /// The squared distance from a point to a line segment, all in map points — squared so a pass
    /// over every leg of a route needs no square root.
    ///
    /// The same question is asked by two callers of the same geometry: a tap asks which route it
    /// landed on, the route editor's eraser asks which legs its stroke reached. Neither can afford
    /// a `CLLocation` per leg, and a route is redrawn on every fix of a walk, so the maths lives
    /// here once rather than beside each caller.
    static func pointToSegmentSquared(_ point: MKMapPoint,
                                      _ a: MKMapPoint,
                                      _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distanceSquared(point, a) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        return distanceSquared(point, MKMapPoint(x: cx, y: cy))
    }

    /// The squared distance between two points in map points.
    static func distanceSquared(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dx * dx + dy * dy
    }

    /// The initial bearing from one point to another, in degrees from true north.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `fraction` of the way along a polyline, measured by length.
    static func pointAlong(_ coordinates: [CLLocationCoordinate2D],
                           fraction: Double) -> CLLocationCoordinate2D? {
        guard coordinates.count > 1 else { return coordinates.first }
        let total = CoverageIndex.length(of: coordinates)
        guard total > 0 else { return coordinates.first }
        let wanted = total * min(max(fraction, 0), 1)
        var travelled = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let segment = CoverageIndex.meters(from: a, to: b)
            if travelled + segment >= wanted {
                let t = segment > 0 ? (wanted - travelled) / segment : 0
                return CoverageIndex.interpolate(a, b, t)
            }
            travelled += segment
        }
        return coordinates.last
    }

    /// The bearing of the polyline at `fraction` of its length, so a detour can be laid off to
    /// one side of the corridor.
    static func bearingAlong(_ coordinates: [CLLocationCoordinate2D],
                             fraction: Double) -> Double? {
        guard coordinates.count > 1 else { return nil }
        let total = CoverageIndex.length(of: coordinates)
        guard total > 0 else { return nil }
        let wanted = total * min(max(fraction, 0), 1)
        var travelled = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let segment = CoverageIndex.meters(from: a, to: b)
            if travelled + segment >= wanted {
                return bearing(from: a, to: b)
            }
            travelled += segment
        }
        if let a = coordinates.dropLast().last, let b = coordinates.last {
            return bearing(from: a, to: b)
        }
        return nil
    }

    /// The share of a polyline's length that runs back over ground it already covered: the same
    /// street walked twice. Two points count as the same street when they are within
    /// `sameStreetMeters` of each other and the direction of travel at the two points is either
    /// the same or opposite. The first and last `endMeters` of the route are ignored, so a loop
    /// closing at its start is not mistaken for a double-back.
    ///
    /// This is what stops the explorer from offering a route that walks up a street and straight
    /// back down it when the shape's zigzag lands on a road network that forces it. A dead end is
    /// the one time a double-back is unavoidable, and the share it produces is small enough that
    /// the route is still ranked ahead of a genuinely worse one.
    static func backtrackingFraction(of coordinates: [CLLocationCoordinate2D],
                                     sameStreetMeters: Double = 15,
                                     minGapMeters: Double = 40,
                                     bearingTolerance: Double = 45,
                                     endMeters: Double = 30,
                                     sampleMeters: Double = 10) -> Double {
        guard coordinates.count > 2 else { return 0 }

        var samples: [(point: CLLocationCoordinate2D, distance: Double, bearing: Double)] = []
        var cumulative = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let segment = CoverageIndex.meters(from: a, to: b)
            guard segment > 0 else { continue }
            let bearing = Geo.bearing(from: a, to: b)
            let steps = max(1, Int((segment / sampleMeters).rounded()))
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                samples.append((CoverageIndex.interpolate(a, b, t),
                                cumulative + segment * t,
                                bearing))
            }
            cumulative += segment
        }
        guard let last = coordinates.last, let lastBearing = samples.last?.bearing else { return 0 }
        samples.append((last, cumulative, lastBearing))

        let total = cumulative
        guard total > 2 * endMeters, samples.count > 2 else { return 0 }

        var backtracked = [Bool](repeating: false, count: samples.count)
        for i in 0..<samples.count {
            let si = samples[i]
            guard si.distance >= endMeters, si.distance <= total - endMeters else { continue }
            for j in 0..<i {
                let sj = samples[j]
                guard sj.distance >= endMeters else { continue }
                guard si.distance - sj.distance > minGapMeters else { continue }
                guard CoverageIndex.meters(from: si.point, to: sj.point) < sameStreetMeters else {
                    continue
                }
                var delta = abs(si.bearing - sj.bearing)
                delta = min(delta, 360 - delta)
                if delta < bearingTolerance || delta > 180 - bearingTolerance {
                    backtracked[i] = true
                    break
                }
            }
        }

        return Double(backtracked.filter { $0 }.count) / Double(samples.count)
    }

    /// The length in metres of a run of legs.
    static func length(_ legs: [DirectionsLeg]) -> Double {
        legs.reduce(0) { $0 + $1.distance }
    }

    /// Stitches consecutive legs into one polyline, dropping the duplicate joint between them.
    static func stitch(_ legs: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
        var stitched: [CLLocationCoordinate2D] = []
        for leg in legs {
            guard let first = leg.first else { continue }
            if let last = stitched.last, same(last, first) {
                stitched.append(contentsOf: leg.dropFirst())
            } else {
                stitched.append(contentsOf: leg)
            }
        }
        return stitched
    }

    static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
    }
}
