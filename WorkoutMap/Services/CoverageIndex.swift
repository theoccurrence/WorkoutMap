import Foundation
import CoreLocation

/// A coarse "have I been here?" index over the workout routes: a grid of ~25 m cells, every
/// known route rasterised into it. A planned route is then scored by how many of its metres
/// fall on cells no workout has touched — the "new ways" the explorer is looking for.
///
/// The grid is square in *degrees* rather than in metres, so away from the equator an
/// east-west cell is narrower than a north-south one (at Munich's latitude ~17 m against
/// 25 m). Both the workouts and the candidates run through the same grid, so the score is
/// consistent; only the absolute metre figure carries the anisotropy, which a "how much of
/// this walk is new" share does not care about.
struct CoverageIndex {
    /// The grid's cell size in metres, north to south.
    static let cellMeters: Double = 25
    /// Degrees of latitude per cell.
    static let cellDegrees: Double = cellMeters / 111_320
    /// How finely a route is sampled while it is rasterised or scored.
    private static let sampleMeters: Double = 12.5

    private var cells: Set<Int64> = []

    var isEmpty: Bool { cells.isEmpty }
    var cellCount: Int { cells.count }

    init() {}

    init(routes: [[CLLocationCoordinate2D]]) {
        for route in routes { insert(route) }
    }

    /// Marks every cell the route passes through as covered.
    mutating func insert(_ coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count > 1 else { return }
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            sample(a, b) { point, _ in cells.insert(CoverageIndex.cell(of: point)) }
        }
    }

    func isCovered(_ coordinate: CLLocationCoordinate2D) -> Bool {
        cells.contains(CoverageIndex.cell(of: coordinate))
    }

    /// The metres of a polyline that lie on ground no workout has covered.
    func uncoveredMeters(of coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var uncovered = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            sample(a, b) { point, step in
                if !cells.contains(CoverageIndex.cell(of: point)) { uncovered += step }
            }
        }
        return uncovered
    }

    /// Walks the segment `a`→`b` in ~`sampleMeters` steps, handing the callback each sample
    /// point and the length of the step it stands for.
    private func sample(_ a: CLLocationCoordinate2D,
                        _ b: CLLocationCoordinate2D,
                        _ body: (CLLocationCoordinate2D, Double) -> Void) {
        let length = CoverageIndex.meters(from: a, to: b)
        guard length > 0 else { return }
        let steps = max(1, Int((length / CoverageIndex.sampleMeters).rounded(.up)))
        let step = length / Double(steps)
        for index in 0..<steps {
            let t = (Double(index) + 0.5) / Double(steps)
            body(CoverageIndex.interpolate(a, b, t), step)
        }
    }

    /// The share of the 3×3 cells around a coordinate that are covered: 0 is ground no workout
    /// has been near, 1 is ground the user has walked through. The window rather than the single
    /// cell because one cell is a coin toss — this is what nudges a turning point towards the
    /// least covered ground nearby, and it should be a street that is empty, not a gap in one.
    func coveredAround(_ coordinate: CLLocationCoordinate2D) -> Double {
        let base = CoverageIndex.indices(of: coordinate)
        var covered = 0
        for deltaX in -1...1 {
            for deltaY in -1...1 {
                if cells.contains(CoverageIndex.cell(base.lat + Int64(deltaY),
                                                     base.lon + Int64(deltaX))) { covered += 1 }
            }
        }
        return Double(covered) / 9
    }

    /// The grid cell a coordinate falls in, packed into one integer. Latitude and longitude
    /// indices each fit in 32 bits, so the two halves never collide.
    private static func cell(of coordinate: CLLocationCoordinate2D) -> Int64 {
        let indices = indices(of: coordinate)
        return cell(indices.lat, indices.lon)
    }

    private static func indices(of coordinate: CLLocationCoordinate2D) -> (lat: Int64, lon: Int64) {
        (Int64((coordinate.latitude / cellDegrees).rounded(.down)),
         Int64((coordinate.longitude / cellDegrees).rounded(.down)))
    }

    private static func cell(_ lat: Int64, _ lon: Int64) -> Int64 {
        (lat << 32) ^ (lon & 0xFFFF_FFFF)
    }

    /// Equirectangular distance, good enough for the few hundred metres one segment spans.
    static func meters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let dLat = (b.latitude - a.latitude) * 111_320
        let midLat = (a.latitude + b.latitude) / 2 * .pi / 180
        let dLon = (b.longitude - a.longitude) * 111_320 * cos(midLat)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    static func interpolate(_ a: CLLocationCoordinate2D,
                            _ b: CLLocationCoordinate2D,
                            _ t: Double) -> CLLocationCoordinate2D {
        let delta = ((b.longitude - a.longitude + 540).truncatingRemainder(dividingBy: 360)) - 180
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + delta * t)
    }

    /// The length of a polyline in metres.
    static func length(of coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) { total += meters(from: a, to: b) }
        return total
    }
}
