import Foundation
import CoreLocation

/// One workout’s GPS track, with the legs the receiver made up told apart from the legs the
/// user actually walked.
///
/// Health hands a workout route over as the fixes the receiver took, roughly one per second.
/// When it loses its fix the position reported next can be somewhere it never was — hundreds of
/// metres away within the time one fix takes — and the polyline joins the two points with a
/// straight line across whatever lies between them: houses, gardens, a lake. The Fitness app
/// does not draw such a leg as ground the user covered; it draws it as a dotted grey line
/// (see `RouteJumpStyle`). This type carries, per leg, how long the receiver took over it, so a
/// leg can be judged when it is drawn.
struct WorkoutRoute {
    /// The fixes, in the order the receiver took them.
    var coordinates: [CLLocationCoordinate2D]
    /// The seconds between the fix that ends each leg and the one before it: `intervals[i]`
    /// belongs to the leg arriving at `coordinates[i]`. `0` for the first fix, and for a fix
    /// whose timestamp could not be used.
    ///
    /// Kept beside the coordinates rather than baked into a jump flag: what counts as a jump is
    /// a setting, so a threshold can change without the route having to be fetched from Health
    /// again.
    var intervals: [Double]

    init(coordinates: [CLLocationCoordinate2D], intervals: [Double] = []) {
        self.coordinates = coordinates
        self.intervals = intervals.count == coordinates.count
            ? intervals
            : Array(repeating: 0, count: coordinates.count)
    }

    /// The track as Health has it, with the interval each leg took.
    init(locations: [CLLocation]) {
        self.coordinates = locations.map(\.coordinate)
        self.intervals = [0] + zip(locations.dropFirst(), locations).map {
            $0.timestamp.timeIntervalSince($1.timestamp)
        }
    }

    var isEmpty: Bool { coordinates.isEmpty }
    var count: Int { coordinates.count }

    // MARK: the strict detection

    /// How fast a leg would have to be to still be the user moving: a jump beats 162 km/h,
    /// which is past any human and past a car on a country road, and covers at least 25 m, so a
    /// duplicate fix a metre away in a hundredth of a second — a badly rounded timestamp, not a
    /// jump — is let through. The plain-distance limit is what is left when a sample carries no
    /// usable timestamp at all: no fix interval can cover that much ground at any speed.
    static let implausibleSpeed: Double = 45          // m/s ≈ 162 km/h
    static let jumpMinimumDistance: Double = 25       // m
    static let jumpDistanceWithoutTime: Double = 300  // m

    /// The distance of the leg arriving at `index`, in metres.
    ///
    /// A great-circle distance rather than `CLLocation.distance(from:)`: the routes are judged
    /// again every time they are drawn — a new fix every second redraws the map — and a
    /// threshold test 5–300 m long needs neither a geodesic solver nor two `CLLocation` objects
    /// per leg.
    func legDistance(_ index: Int) -> Double {
        guard index > 0, index < coordinates.count else { return 0 }
        let a = coordinates[index - 1]
        let b = coordinates[index]
        let radians = Double.pi / 180
        let halfLat = (b.latitude - a.latitude) * radians / 2
        let halfLon = (b.longitude - a.longitude) * radians / 2
        let h = sin(halfLat) * sin(halfLat)
            + cos(a.latitude * radians) * cos(b.latitude * radians) * sin(halfLon) * sin(halfLon)
        return 2 * 6_371_000 * asin(min(1, h.squareRoot()))
    }

    /// How fast the leg arriving at `index` was, in metres per second, or `nil` when the fixes
    /// carry no usable interval — a rounded or out-of-order timestamp, which is what the plain
    /// distance test is left for.
    func legSpeed(_ index: Int) -> Double? {
        guard index > 0, index < intervals.count, intervals[index] > 0 else { return nil }
        return legDistance(index) / intervals[index]
    }

    // MARK: drawing

    /// How a track is split up for drawing.
    struct Drawing {
        /// The stretches the user walked, separated where a jump interrupts them.
        let walked: [[CLLocationCoordinate2D]]
        /// The legs drawn as a line of their own, in the order they run.
        let legs: [JumpLeg]
    }

    /// One leg to draw, and what caught it.
    struct JumpLeg {
        let coordinates: [CLLocationCoordinate2D]
        let kind: JumpKind
    }

    /// The fixes that are still drawn after `erased` took some legs out — a fix is kept while a
    /// leg on either side of it is. What frames the map on a route the user has edited uses this,
    /// so an erased stretch does not leave a hole of empty map beside the route.
    func visible(erased: EraseEdits) -> [CLLocationCoordinate2D] {
        guard !erased.isEmpty else { return coordinates }
        var kept: [CLLocationCoordinate2D] = []
        kept.reserveCapacity(coordinates.count)
        for index in coordinates.indices {
            let before = index > 0 && !erased.contains(index)
            let after = index + 1 < coordinates.count && !erased.contains(index + 1)
            if before || after { kept.append(coordinates[index]) }
        }
        return kept
    }

    /// Splits the track the way `rules` say it should be drawn, with the legs `erased` took out.
    ///
    /// A leg the **strict** three-part rule catches is never drawn — it is the receiver's
    /// invention, and the map simply leaves the ground out. The two softer rules are each on
    /// their own: a leg longer than the distance threshold is a distance leg, a leg that covers
    /// `JumpRules.speedMinimumDistance` and is faster than the speed threshold is a speed leg,
    /// and a leg that trips both is a speed leg. A leg whose
    /// rule is set to `hidden` still splits the walked line — the gap is the point — but no line
    /// is drawn for it.
    ///
    /// An erased leg is a leg that is not drawn **at all** — walked or jump. That is what lets the
    /// eraser take a dotted jump leg out as readily as a stretch of the walked line: the dotted
    /// line *is* one leg. Because the drawing only ever emits the legs it is given and never
    /// invents one between two fixes an erasure separated, erasing a stretch of the route cannot
    /// leave a phantom line across the gap.
    func drawing(_ rules: JumpRules, erased: EraseEdits = .empty) -> Drawing {
        guard coordinates.count > 1 else { return Drawing(walked: [coordinates], legs: []) }
        var walked: [[CLLocationCoordinate2D]] = []
        var legs: [JumpLeg] = []
        var run: [CLLocationCoordinate2D] = []
        for index in 1..<coordinates.count {
            // The line simply stops where it was erased and picks up at the leg after it.
            guard !erased.contains(index) else {
                if run.count > 1 { walked.append(run) }
                run = []
                continue
            }
            let distance = legDistance(index)
            let speed = legSpeed(index)
            let strict = distance > Self.jumpMinimumDistance
                && (speed.map { $0 > Self.implausibleSpeed } ?? (distance > Self.jumpDistanceWithoutTime))
            let kind: JumpKind?
            if strict {
                kind = nil
            } else if let speed, distance > JumpRules.speedMinimumDistance,
                      speed > rules.speedThresholdMetersPerSecond {
                kind = .speed
            } else if distance > rules.distanceThreshold {
                kind = .distance
            } else {
                kind = nil
            }
            if strict || kind != nil {
                if run.count > 1 { walked.append(run) }
                run = []
                if let kind, rules.style(for: kind) != .hidden {
                    legs.append(JumpLeg(coordinates: [coordinates[index - 1], coordinates[index]], kind: kind))
                }
                continue
            }
            // A walked leg joins the run, and the run has to start at the leg's own first fix:
            // the leg before it may have been erased, or may have been a jump, and a fix that is
            // no longer joined to anything must not be drawn on its own.
            if run.isEmpty { run = [coordinates[index - 1]] }
            run.append(coordinates[index])
        }
        if run.count > 1 { walked.append(run) }
        return Drawing(walked: walked, legs: legs)
    }
}
