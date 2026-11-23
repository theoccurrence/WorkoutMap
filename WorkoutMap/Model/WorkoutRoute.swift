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

    // MARK: judging a leg

    /// Whether the receiver cannot have made this leg: the **strict** three-part rule. Such a leg is
    /// the receiver's invention, never drawn, and not a jump a rule judges — so the route editor's
    /// *valid* tool will not flag it either.
    static func isImplausible(distance: Double, speed: Double?) -> Bool {
        distance > jumpMinimumDistance
            && (speed.map { $0 > implausibleSpeed } ?? (distance > jumpDistanceWithoutTime))
    }

    /// What **softer** rule catches this leg, or `nil` when none does — an ordinary leg, or one the
    /// strict rule already owns. The route editor asks this to know which legs are its to flag:
    /// flagging an ordinary leg would say nothing, and flagging a leg the receiver invented would
    /// draw a line across ground nobody covered.
    static func jumpKind(distance: Double, speed: Double?, rules: JumpRules) -> JumpKind? {
        guard !isImplausible(distance: distance, speed: speed) else { return nil }
        if let speed, distance > JumpRules.speedMinimumDistance,
           speed > rules.speedThresholdMetersPerSecond {
            return .speed
        }
        if distance > rules.distanceThreshold {
            return .distance
        }
        return nil
    }

    func isImplausible(_ index: Int) -> Bool {
        Self.isImplausible(distance: legDistance(index), speed: legSpeed(index))
    }

    func jumpKind(_ index: Int, rules: JumpRules) -> JumpKind? {
        Self.jumpKind(distance: legDistance(index), speed: legSpeed(index), rules: rules)
    }

    // MARK: drawing

    /// How a track is split up for drawing.
    struct Drawing {
        /// The stretches the user walked, separated where a jump interrupts them. A leg the user has
        /// flagged as ground they covered joins these, unless the drawing is one that shows the flag
        /// (see `showValidatedJumps`).
        let walked: [[CLLocationCoordinate2D]]
        /// The legs drawn as a line of their own, in the order they run.
        let legs: [JumpLeg]
        /// The flagged legs the drawing still shows as the jumps they are — `showValidatedJumps`
        /// only, and empty otherwise.
        let validated: [[CLLocationCoordinate2D]]
    }

    /// One leg to draw, and what caught it.
    struct JumpLeg {
        let coordinates: [CLLocationCoordinate2D]
        let kind: JumpKind
    }

    /// The fixes that are still drawn after `edits` took some legs out — a fix is kept while a leg
    /// on either side of it is. What frames the map on a route the user has edited uses this, so an
    /// erased stretch does not leave a hole of empty map beside the route. A flagged leg is drawn,
    /// so it keeps its fixes.
    func visible(_ edits: RouteEdits) -> [CLLocationCoordinate2D] {
        guard !edits.erased.isEmpty else { return coordinates }
        var kept: [CLLocationCoordinate2D] = []
        kept.reserveCapacity(coordinates.count)
        for index in coordinates.indices {
            let before = index > 0 && !edits.erased.contains(index)
            let after = index + 1 < coordinates.count && !edits.erased.contains(index + 1)
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
    ///
    /// A leg the user **flagged** as ground they covered is the opposite statement: the softer rules
    /// are not asked about it, and `showValidatedJumps` alone decides how it is drawn. Off — the map,
    /// the list and the export from them — it joins the walked line and simply *is* the route, which
    /// is the whole point of flagging it. On — the workout's own screens — it comes back as the jump
    /// it still is, in `Drawing.validated`, so the flag can be seen where it can also be changed.
    func drawing(_ rules: JumpRules,
                 edits: RouteEdits = .empty,
                 showValidatedJumps: Bool = false) -> Drawing {
        guard coordinates.count > 1 else {
            return Drawing(walked: [coordinates], legs: [], validated: [])
        }
        var walked: [[CLLocationCoordinate2D]] = []
        var legs: [JumpLeg] = []
        var validated: [[CLLocationCoordinate2D]] = []
        var run: [CLLocationCoordinate2D] = []
        for index in 1..<coordinates.count {
            // The line simply stops where it was erased and picks up at the leg after it.
            guard !edits.erased.contains(index) else {
                if run.count > 1 { walked.append(run) }
                run = []
                continue
            }
            let leg = [self.coordinates[index - 1], self.coordinates[index]]
            if edits.validated.contains(index) {
                if showValidatedJumps {
                    if run.count > 1 { walked.append(run) }
                    run = []
                    validated.append(leg)
                    continue
                }
                // Flagged and not being shown as a jump: the leg is ground the user covered, like
                // any other walked leg, and joins the run.
                if run.isEmpty { run = [leg[0]] }
                run.append(leg[1])
                continue
            }
            let distance = legDistance(index)
            let speed = legSpeed(index)
            if Self.isImplausible(distance: distance, speed: speed) {
                if run.count > 1 { walked.append(run) }
                run = []
                continue
            }
            if let kind = Self.jumpKind(distance: distance, speed: speed, rules: rules) {
                if run.count > 1 { walked.append(run) }
                run = []
                if rules.style(for: kind) != .hidden {
                    legs.append(JumpLeg(coordinates: leg, kind: kind))
                }
                continue
            }
            // A walked leg joins the run, and the run has to start at the leg's own first fix:
            // the leg before it may have been erased, or may have been a jump, and a fix that is
            // no longer joined to anything must not be drawn on its own.
            if run.isEmpty { run = [leg[0]] }
            run.append(leg[1])
        }
        if run.count > 1 { walked.append(run) }
        return Drawing(walked: walked, legs: legs, validated: validated)
    }
}
