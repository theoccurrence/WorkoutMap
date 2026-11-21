import Foundation
import CoreLocation

/// Plans a walk that covers as much ground as possible the user has never covered.
///
/// Two algorithms live here, and `strategy` picks one:
///
/// * **zigzag** — the shape is a zigzag sized so its straight-line length is the distance asked
///   for, and the setting that matters is how many legs it is made of: a few long ones reach far
///   out, many short ones fill the streets around the route instead. The distance is held
///   roughly constant while the *shape* changes, which is the whole point of the setting.
/// * **tour** — the shape is a disc of ground, sized so that the streets in it are the distance
///   asked for, and the route sweeps it row by row. The rows are the shape setting: a tight tour
///   is many short rows over a small disc, a wide one is a couple of long rows over a big one.
///   Rows that hold no new ground are dropped, so a tight tour spends its legs on the streets
///   the user has not walked instead of re-walking the ones they know by heart.
///
/// Both share the same machinery: candidates are scored against the coverage grid *before*
/// anything is routed, so only the best few ever reach the service, and `MKDirections` knows no
/// waypoints, so every shape is a handful of point-to-point legs stitched into one polyline.
struct RoutePlanner {
    struct Config {
        /// How many shapes are scored before any network request, at the start itself.
        var candidates = 8
        /// And how many more on rings around it — the ground under the user's feet is the ground
        /// they have covered most, so a loop that only ever centres there can never be mostly
        /// new. Each factor is a share of the radius a circle of the requested length would have.
        var ringFactors: [Double] = [0.45, 0.9, 1.4, 2.0]
        var ringBearings = 6
        /// How many `MKDirections` calls run at once — the service throttles a burst
        /// (`MKError.Code.loadingThrottled`).
        var maxConcurrentLegs = 3
        /// How much of a candidate's pre-score is random, so the same request varies.
        var noise = 0.25
        /// How far off the requested distance a route may land before it is pushed to the back.
        var distanceTolerance = 0.35
        /// How much longer a real route is than the straight line its shape is sized on. A
        /// tighter shape turns more often and follows more side streets, so its real length runs
        /// further ahead of the straight line — hence the slope on top of it.
        var roadFactor = 1.32
        var roadFactorSlope = 0.18
        /// How much a route is docked for heading where a recent plan already went.
        var recencyPenalty = 0.5
        /// The angular window of that dock, in degrees.
        var recencyWindowDegrees = 70.0
        /// The most legs one route may be made of, and the most a whole plan may cost. The
        /// second is the ceiling the settings' own maximums ask for — five routes of five legs —
        /// plus a little slack, so asking for five routes never silently yields three. What
        /// keeps a burst from being throttled is `maxConcurrentLegs` and the retry, not this.
        var maxLegsPerRoute = 5
        var maxLegsPerPlan = 30

        // MARK: Tour

        /// How many rows the tour's serpentine is made of at the tightest and the widest shape.
        /// Tight is many short rows over a small disc, wide a couple of long ones over a big one,
        /// and the disc is sized so the sweep is still the distance asked for.
        var tourRowsTight = 6
        var tourRowsWide = 2
        /// Where the tour's disc may sit: how many bearings are tried, and how far out along each
        /// it slides as a share of its *own* radius — so the start always stays inside it. Factor
        /// 0 is the start itself, so a disc that centres there is always among the candidates.
        var tourCentreBearings = 10
        var tourCentreFactors: [Double] = [0, 0.5, 0.9]
        /// The least uncovered metres a row must hold to be walked at all. A row that is covered
        /// ground from end to end is dropped, which is what keeps a tight sweep on the streets
        /// the user has not walked instead of re-walking the ones they know by heart.
        var tourRowMinNewMeters = 30.0
        /// How many samples across a disc are taken when its unexplored density is scored.
        var tourDensitySamples = 11
        /// How much a tour route is docked for a centre away from the start, per radius — what
        /// keeps a tight sweep near the user rather than out where the map happens to be emptiest.
        var tourCentrePenalty = 0.35
        /// How much any route is docked for re-walking ground it has already walked. Applies to
        /// both algorithms: a street walked twice is a street not walked somewhere else.
        var backtrackPenalty = 0.8
        /// The tour's own leg budget. A sweep is a row per leg and then some, so it asks the
        /// service for more legs than the zigzag does; the plan cap is the ceiling the settings'
        /// maximums ask for, five routes of a full sweep.
        var tourMaxLegsPerRoute = 14
        var tourMaxLegsPerPlan = 45

        /// The number of legs a shape asks for: one at the widest, five at the tightest.
        static func steps(for shape: Double) -> Int {
            1 + Int((min(max(shape, 0), 1) * 4).rounded())
        }
    }

    var config = Config()
    /// Which algorithm plans the route — see `PlanStrategy`. The tour is the proof of concept,
    /// so it is the default; `WM_PLAN_ALGO=zigzag` puts the shipped zigzag back.
    var strategy: PlanStrategy = .tour
    /// How many routes the settings ask for.
    var routeCount = ExploreOptions.routeCountDefault
    /// How tight the shape should be, 0...1 — see `ExploreOptions.shapeKey`.
    var shape = ExploreOptions.shapeDefault
    /// How much of the route should be new ground, 0...1 — see `ExploreOptions.minimumNewKey`.
    /// A target rather than a guarantee: it decides where the planner looks and what it ranks
    /// first, and the card says what actually came back.
    var minimumNew = ExploreOptions.minimumNewDefault
    var seed: UInt64 = UInt64.random(in: .min ... .max)

    /// How much longer a real route runs than the straight line its shape is sized on, at the
    /// shape the settings are asking for.
    private var roadFactor: Double {
        config.roadFactor + config.roadFactorSlope * min(max(shape, 0), 1)
    }

    func plan(request: PlanRequest,
              start: CLLocationCoordinate2D,
              coverage: CoverageIndex,
              client: DirectionsClient) async -> RoutePlan? {
        switch strategy {
        case .zigzag:
            return await planZigzag(request: request, start: start, coverage: coverage, client: client)
        case .tour:
            if let plan = await planTour(request: request, start: start,
                                         coverage: coverage, client: client) {
                return plan
            }
            // Nothing to tour: every street the disc could hold is walked already, so there is no
            // row left to sweep. The zigzag will still offer a walk, which is better than a card
            // that says there is nothing.
            return await planZigzag(request: request, start: start, coverage: coverage, client: client)
        }
    }

    private func planZigzag(request: PlanRequest,
                            start: CLLocationCoordinate2D,
                            coverage: CoverageIndex,
                            client: DirectionsClient) async -> RoutePlan? {
        switch request.mode {
        case .loop:
            return await planLoop(request: request, start: start, coverage: coverage, client: client)
        case .destination:
            return await planDestination(request: request, start: start, coverage: coverage, client: client)
        }
    }

    private func planTour(request: PlanRequest,
                          start: CLLocationCoordinate2D,
                          coverage: CoverageIndex,
                          client: DirectionsClient) async -> RoutePlan? {
        switch request.mode {
        case .loop:
            return await planTourLoop(request: request, start: start, coverage: coverage, client: client)
        case .destination:
            return await planTourDestination(request: request, start: start, coverage: coverage, client: client)
        }
    }

    // MARK: - Loop

    private func planLoop(request: PlanRequest,
                          start: CLLocationCoordinate2D,
                          coverage: CoverageIndex,
                          client: DirectionsClient) async -> RoutePlan? {
        let target = max(200, request.targetMeters)
        var generator = SplitMix64(seed: seed)
        let history = PlanHistory.load()
        // How tight the shape is: the setting, but pulled tighter still when the user is asking
        // for a lot of new ground — filling the streets around the route is how that is found.
        let steps = max(2, min(config.maxLegsPerRoute,
                               Config.steps(for: max(shape, minimumNew))))

        var candidates: [(waypoints: [CLLocationCoordinate2D], rough: Double)] = []
        for centre in loopCentres(start: start, target: target, generator: &generator) {
            // A little wobble on every turning point, so two shapes that set off the same way are
            // still not the same walk.
            let jitters = (0..<steps).map { _ in
                (along: Double.random(in: -0.16...0.16, using: &generator),
                 across: Double.random(in: -0.16...0.16, using: &generator))
            }
            guard let waypoints = loopShape(start: start, centre: centre.centre,
                                            bearing: centre.bearing, steps: steps,
                                            target: target, roadFactor: roadFactor,
                                            coverage: coverage, jitters: jitters) else { continue }

            let straight = [start] + waypoints + [start]
            let length: Double = max(1, CoverageIndex.length(of: straight))
            let uncovered: Double = coverage.uncoveredMeters(of: straight)
            let fraction: Double = uncovered / length
            let fit: Double = 1 - min(1, abs(length - target) / target)
            let penalty: Double = history.penalty(start: start, bearing: centre.bearing,
                                                  meters: target, config: config)
            let shortfall: Double = max(0, minimumNew - fraction)
            let noise: Double = Double.random(in: -1...1, using: &generator)
            let rough: Double = fraction + 0.3 * fit - penalty - 3 * shortfall
                + config.noise * noise
            candidates.append((waypoints, rough))
        }

        let budget = max(1, config.maxLegsPerPlan / steps)
        let wanted = max(1, min(routeCount, budget))
        let finalists = candidates.sorted { $0.rough > $1.rough }.prefix(wanted)

        var routed: [PlannedRoute] = []
        for (index, candidate) in finalists.enumerated() {
            let points = [start] + candidate.waypoints + [start]
            let pairs = zip(points, points.dropFirst()).map { (from: $0, to: $1) }
            guard let legs = await route(Array(pairs), client: client),
                  let made = makeRoute(id: index, legs: legs, coverage: coverage) else { continue }
            routed.append(made)
        }
        guard !routed.isEmpty else { return nil }

        let plan = finalize(request: request, start: start, routes: routed, history: history, coverage: coverage)
        record(plan, start: start, request: request)
        return plan
    }

    /// Where the loop's zigzag is tried: at the start itself, and then on rings around it. The
    /// ground right under the user's feet is the ground they have covered most, so a shape that
    /// only ever centres there can never be mostly new — a park two streets away whose little
    /// paths were never walked can.
    private func loopCentres(start: CLLocationCoordinate2D,
                             target: Double,
                             generator: inout SplitMix64) -> [(centre: CLLocationCoordinate2D, bearing: Double)] {
        let reach = target / (2 * .pi)
        var centres: [(centre: CLLocationCoordinate2D, bearing: Double)] = []
        for index in 0..<config.candidates {
            let base = Double(index) / Double(config.candidates) * 360
            let bearing = (base + Double.random(in: -22...22, using: &generator))
                .truncatingRemainder(dividingBy: 360)
            centres.append((start, bearing))
        }
        for factor in config.ringFactors {
            for index in 0..<config.ringBearings {
                let base = Double(index) / Double(config.ringBearings) * 360
                let bearing = base + Double.random(in: -18...18, using: &generator)
                let centre = Geo.destination(from: start, bearing: bearing, distance: reach * factor)
                let row = (bearing + Double.random(in: -35...35, using: &generator))
                    .truncatingRemainder(dividingBy: 360)
                centres.append((centre, row))
            }
        }
        return centres
    }

    /// A loop as a zigzag over a square centred on `centre`: `steps` rows, the route turning at
    /// each row's far end, and the start as both ends of the whole thing.
    ///
    /// The square is sized by bisection so the zigzag's straight-line length is the distance
    /// asked for — including the legs out to a square that is not centred on the start, which is
    /// what rules out a centre too far away to be reached and still come back. `roadFactor`
    /// corrects for a real route being longer than the straight lines it follows.
    ///
    /// Returns `nil` when even a square of no size cannot be reached and returned within the
    /// distance, which is what prunes the far rings.
    private func loopShape(start: CLLocationCoordinate2D,
                           centre: CLLocationCoordinate2D,
                           bearing: Double,
                           steps: Int,
                           target: Double,
                           roadFactor: Double,
                           coverage: CoverageIndex,
                           jitters: [(along: Double, across: Double)]) -> [CLLocationCoordinate2D]? {
        func points(scale: Double) -> [CLLocationCoordinate2D] {
            let radians = bearing * .pi / 180
            let spacing = 2 * scale / Double(steps)
            return (0..<steps).map { row in
                let jitter = row < jitters.count ? jitters[row] : (along: 0, across: 0)
                let along = (row.isMultiple(of: 2) ? scale : -scale) * (1 + jitter.along)
                let across = -scale + (Double(row) + 0.5) * spacing + scale * jitter.across
                return Geo.offset(centre,
                                  east: along * sin(radians) + across * cos(radians),
                                  north: along * cos(radians) - across * sin(radians))
            }
        }
        func length(_ scale: Double) -> Double {
            CoverageIndex.length(of: [start] + points(scale: scale) + [start])
        }

        let wanted = target / roadFactor
        var low = 0.0
        var high = max(50, target)
        guard length(high) > wanted else {
            let sized = points(scale: high)
            return sized.map { bias($0, across: bearing, span: high * 0.3, coverage: coverage) }
        }
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if length(mid) < wanted { low = mid } else { high = mid }
        }
        let scale = (low + high) / 2
        // The start has to be reached and left again whatever the square does.
        guard scale > 1 else { return nil }
        return points(scale: scale).map {
            bias($0, across: bearing, span: scale * 0.3, coverage: coverage)
        }
    }

    /// Slides a turning point across its row until it sits on the least covered ground within
    /// `span`. The whole point of the feature is to walk the streets that are not covered, and a
    /// waypoint a hundred metres to one side can be in a park while this one is on a road the
    /// user runs every week.
    private func bias(_ waypoint: CLLocationCoordinate2D,
                      across bearing: Double,
                      span: Double,
                      coverage: CoverageIndex) -> CLLocationCoordinate2D {
        guard span > 1 else { return waypoint }
        var best = waypoint
        var bestScore = coverage.coveredAround(waypoint)
        for step in [-3, -2, -1, 1, 2, 3] {
            let candidate = Geo.destination(from: waypoint, bearing: bearing + 90,
                                            distance: Double(step) / 3 * span)
            let score = coverage.coveredAround(candidate)
            if score < bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    // MARK: - Destination

    private func planDestination(request: PlanRequest,
                                 start: CLLocationCoordinate2D,
                                 coverage: CoverageIndex,
                                 client: DirectionsClient) async -> RoutePlan? {
        guard let destination = request.destination,
              !Geo.same(start, destination) else { return nil }
        let target = max(200, request.targetMeters)
        let history = PlanHistory.load()
        let steps = min(config.maxLegsPerRoute,
                        max(1, Config.steps(for: max(shape, minimumNew))))

        guard let directLegs = try? await client.route(from: start, to: destination),
              let direct = directLegs.first else { return nil }

        var routed: [PlannedRoute] = []
        if let made = makeRoute(id: 0, legs: [direct], coverage: coverage) { routed.append(made) }

        // A detour only makes sense when the user wants to walk farther than the direct way.
        if target > direct.distance * 1.05 {
            var generator = SplitMix64(seed: seed &+ 1)
            let jitters = [Double.random(in: -10...10, using: &generator),
                           Double.random(in: -10...10, using: &generator)]

            var rounds: [(side: Double, jitter: Double, legs: [DirectionsLeg])] = []
            async let left = detourRound(start: start, destination: destination, steps: steps,
                                         side: -1, jitter: jitters[0], target: target,
                                         offset: nil, coverage: coverage, client: client)
            async let right = detourRound(start: start, destination: destination, steps: steps,
                                          side: 1, jitter: jitters[1], target: target,
                                          offset: nil, coverage: coverage, client: client)
            if let legs = await left { rounds.append((-1, jitters[0], legs)) }
            if let legs = await right { rounds.append((1, jitters[1], legs)) }

            // One correction round on the better of the two: the shape is sized on straight
            // lines, so the first routed length can still be a way off.
            let error: (Int) -> Double = { abs(Geo.length(rounds[$0].legs) - target) }
            if let best = rounds.indices.max(by: { error($0) > error($1) }),
               error(best) > target * 0.15 {
                let chosen = rounds[best]
                let extra = Geo.length(chosen.legs) - direct.distance
                if extra > 1 {
                    let base = detourOffset(start: start, destination: destination, steps: steps,
                                            side: chosen.side, target: target)
                    let corrected = max(20, base * (target - direct.distance) / extra)
                    if let legs = await detourRound(start: start, destination: destination, steps: steps,
                                                    side: chosen.side, jitter: chosen.jitter,
                                                    target: target, offset: corrected,
                                                    coverage: coverage, client: client) {
                        rounds[best].legs = legs
                    }
                }
            }

            for round in rounds {
                if let made = makeRoute(id: routed.count, legs: round.legs, coverage: coverage) {
                    routed.append(made)
                }
            }
        } else {
            for leg in directLegs.dropFirst().prefix(2) {
                if let made = makeRoute(id: routed.count, legs: [leg], coverage: coverage) {
                    routed.append(made)
                }
            }
        }

        guard !routed.isEmpty else { return nil }
        let plan = finalize(request: request, start: start, routes: routed, history: history, coverage: coverage)
        record(plan, start: start, request: request)
        return plan
    }

    /// One round of a destination zigzag: builds the shape at `offset` — or at the offset the
    /// straight line asks for — and routes it.
    private func detourRound(start: CLLocationCoordinate2D,
                             destination: CLLocationCoordinate2D,
                             steps: Int,
                             side: Double,
                             jitter: Double,
                             target: Double,
                             offset: Double?,
                             coverage: CoverageIndex,
                             client: DirectionsClient) async -> [DirectionsLeg]? {
        let reach = offset ?? detourOffset(start: start, destination: destination,
                                           steps: steps, side: side, target: target)
        guard reach > 1 else { return nil }
        let waypoints = destinationShape(start: start, destination: destination, steps: steps,
                                         side: side, jitter: jitter, offset: reach,
                                         coverage: coverage)
        let points = [start] + waypoints + [destination]
        let pairs = zip(points, points.dropFirst()).map { (from: $0, to: $1) }
        return await route(Array(pairs), client: client)
    }

    /// The lateral reach whose *straight-line* zigzag is the distance asked for. Bisection
    /// because the length is a sum of square roots and not linear in the reach.
    private func detourOffset(start: CLLocationCoordinate2D,
                              destination: CLLocationCoordinate2D,
                              steps: Int,
                              side: Double,
                              target: Double) -> Double {
        let wanted = target / roadFactor
        func length(_ offset: Double) -> Double {
            CoverageIndex.length(of: [start]
                + destinationShape(start: start, destination: destination, steps: steps,
                                   side: side, jitter: 0, offset: offset, coverage: nil)
                + [destination])
        }
        var low = 0.0
        var high = max(200, target)
        guard length(high) > wanted else { return high }
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if length(mid) < wanted { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// The waypoints of a destination zigzag: `steps` points marching from the start to the
    /// destination, alternating either side of the straight line between them.
    private func destinationShape(start: CLLocationCoordinate2D,
                                  destination: CLLocationCoordinate2D,
                                  steps: Int,
                                  side: Double,
                                  jitter: Double,
                                  offset: Double,
                                  coverage: CoverageIndex?) -> [CLLocationCoordinate2D] {
        let corridor = Geo.bearing(from: start, to: destination)
        let radians = (corridor + jitter + side * 90) * .pi / 180
        return (0..<steps).map { index in
            let base = CoverageIndex.interpolate(start, destination,
                                                 Double(index + 1) / Double(steps + 1))
            let reach = offset * (index.isMultiple(of: 2) ? 1 : -1)
            let waypoint = Geo.offset(base, east: reach * sin(radians), north: reach * cos(radians))
            guard let coverage else { return waypoint }
            // Side streets, not the main road the user takes every day.
            return bias(waypoint, across: corridor, span: offset * 0.4, coverage: coverage)
        }
    }

    // MARK: - Tour

    /// The tour, loop mode: a disc of ground around the user is sized so the streets in it are
    /// the distance asked for, and the walk sweeps it row by row — a lawnmower over the new
    /// ground rather than a zigzag past it.
    ///
    /// The disc is not fixed at the start: it is tried at the start and on a few rings around it,
    /// and a centre is preferred when the ground inside it is unexplored and it is near the user.
    /// That is the answer to the zigzag's habit of ignoring the new streets under the user's feet
    /// in favour of a bigger, emptier square further out — a tour that centres at the start and
    /// fills what is there wins on both counts.
    ///
    /// A row that is covered ground from end to end is dropped before anything is routed, so a
    /// tight tour spends its legs on the streets the user has not walked. The rows that remain
    /// are nudged, at each end, towards the least covered ground nearby, which is what puts a
    /// turning point on the street that is new rather than on the one the user runs every week.
    private func planTourLoop(request: PlanRequest,
                              start: CLLocationCoordinate2D,
                              coverage: CoverageIndex,
                              client: DirectionsClient) async -> RoutePlan? {
        let target = max(200, request.targetMeters)
        var generator = SplitMix64(seed: seed)
        let history = PlanHistory.load()
        let rows = tourRows()

        var candidates: [(waypoints: [CLLocationCoordinate2D], rough: Double)] = []
        for placement in tourPlacements(generator: &generator) {
            // A little wobble on the rows, so two sweeps that cover the same ground are still not
            // the same walk.
            let jitters = (0..<rows).map { _ in
                (along: Double.random(in: -0.08...0.08, using: &generator),
                 across: Double.random(in: -0.12...0.12, using: &generator))
            }
            // Size a disc at the start first, then slide it out by a share of its own radius —
            // which keeps the start inside it, since a disc can only move that far and still
            // hold the ground it was sized on.
            guard let base = tourLoopSweep(start: start, centre: start, bearing: placement.rowBearing,
                                           rows: rows, target: target, coverage: coverage,
                                           jitters: jitters) else { continue }
            let centre = placement.factor <= 0 ? start
                : Geo.destination(from: start, bearing: placement.offsetBearing,
                                  distance: base.radius * placement.factor)
            let sweep: (waypoints: [CLLocationCoordinate2D], radius: Double)
            if placement.factor <= 0 {
                sweep = base
            } else if let moved = tourLoopSweep(start: start, centre: centre,
                                                bearing: placement.rowBearing, rows: rows,
                                                target: target, coverage: coverage, jitters: jitters) {
                sweep = moved
            } else {
                continue
            }

            let chain = [start] + sweep.waypoints + [start]
            let length = max(1, CoverageIndex.length(of: chain))
            let fraction = coverage.uncoveredMeters(of: chain) / length
            let fit = 1 - min(1, abs(length - target) / target)
            let density = tourDensity(centre: centre, radius: sweep.radius, coverage: coverage)
            let offset = CoverageIndex.meters(from: start, to: centre)
            let proximity = min(1, offset / max(1, sweep.radius))
            let penalty = history.penalty(start: start, bearing: placement.rowBearing,
                                          meters: target, config: config)
            let shortfall = max(0, minimumNew - fraction)
            let noise = Double.random(in: -1...1, using: &generator)
            let rough = fraction + 0.3 * fit + 0.5 * density
                - config.tourCentrePenalty * proximity - penalty - 3 * shortfall
                + config.noise * noise
            candidates.append((sweep.waypoints, rough))
        }

        let legsPerRoute = 2 * rows + 1
        let budget = max(1, config.tourMaxLegsPerPlan / max(1, legsPerRoute))
        let wanted = max(1, min(routeCount, budget))
        let finalists = candidates.sorted { $0.rough > $1.rough }.prefix(wanted)

        var routed: [PlannedRoute] = []
        for (index, candidate) in finalists.enumerated() {
            let points = [start] + candidate.waypoints + [start]
            let pairs = zip(points, points.dropFirst()).map { (from: $0, to: $1) }
            guard let legs = await route(Array(pairs), client: client),
                  let made = makeRoute(id: index, legs: legs, coverage: coverage) else { continue }
            routed.append(made)
        }
        guard !routed.isEmpty else { return nil }

        let plan = finalize(request: request, start: start, routes: routed,
                            history: history, coverage: coverage, tour: true)
        record(plan, start: start, request: request)
        return plan
    }

    /// The tour, destination mode: a corridor between the start and the destination is sized so
    /// the streets across it are the distance asked for, and the walk sweeps across it from one
    /// end to the other — start at one end of the shape, destination at the other. The cross-cuts
    /// that hold no new ground are dropped, exactly as the loop's rows are.
    private func planTourDestination(request: PlanRequest,
                                     start: CLLocationCoordinate2D,
                                     coverage: CoverageIndex,
                                     client: DirectionsClient) async -> RoutePlan? {
        guard let destination = request.destination,
              !Geo.same(start, destination) else { return nil }
        let target = max(200, request.targetMeters)
        let history = PlanHistory.load()
        let rows = tourRows()

        guard let directLegs = try? await client.route(from: start, to: destination),
              let direct = directLegs.first else { return nil }

        var routed: [PlannedRoute] = []
        if let made = makeRoute(id: 0, legs: [direct], coverage: coverage) { routed.append(made) }

        // A sweep only makes sense when the user wants to walk farther than the direct way.
        if target > direct.distance * 1.05 {
            var generator = SplitMix64(seed: seed &+ 1)
            let jitters = [Double.random(in: -12...12, using: &generator),
                           Double.random(in: -12...12, using: &generator)]
            for (index, side) in [-1.0, 1.0].enumerated() {
                if let legs = await tourCorridor(start: start, destination: destination, rows: rows,
                                                 side: side, jitter: jitters[index], target: target,
                                                 coverage: coverage, client: client),
                   let made = makeRoute(id: routed.count, legs: legs, coverage: coverage) {
                    routed.append(made)
                }
            }
        } else {
            for leg in directLegs.dropFirst().prefix(2) {
                if let made = makeRoute(id: routed.count, legs: [leg], coverage: coverage) {
                    routed.append(made)
                }
            }
        }

        guard !routed.isEmpty else { return nil }
        let plan = finalize(request: request, start: start, routes: routed,
                            history: history, coverage: coverage, tour: true)
        record(plan, start: start, request: request)
        return plan
    }

    /// How many rows the tour's sweep is made of: many at the tightest, a couple at the widest,
    /// and pulled tighter still when the user is asking for a lot of new ground. Capped by the
    /// leg budget, since a sweep is a row per leg and then some.
    private func tourRows() -> Int {
        let tight = min(max(max(shape, minimumNew), 0), 1)
        let rows = Double(config.tourRowsWide)
            + (Double(config.tourRowsTight) - Double(config.tourRowsWide)) * tight
        return max(2, min((config.tourMaxLegsPerRoute - 1) / 2, Int(rows.rounded())))
    }

    /// Where the tour's disc is tried: the bearings a centre may be offset along, the direction
    /// its rows run in, and how far out it slides as a share of its own radius. Factor 0 is the
    /// start itself, so a disc that centres there is always among the candidates.
    private func tourPlacements(generator: inout SplitMix64)
    -> [(offsetBearing: Double, rowBearing: Double, factor: Double)] {
        var placements: [(offsetBearing: Double, rowBearing: Double, factor: Double)] = []
        for factor in config.tourCentreFactors {
            for index in 0..<config.tourCentreBearings {
                let base = Double(index) / Double(config.tourCentreBearings) * 360
                let offset = (base + Double.random(in: -18...18, using: &generator))
                    .truncatingRemainder(dividingBy: 360)
                let row = (offset + Double.random(in: -45...45, using: &generator))
                    .truncatingRemainder(dividingBy: 360)
                placements.append((offset, row, factor))
            }
        }
        return placements
    }

    /// A tour sweep as the ordered row ends of a serpentine over a disc: `rows` lines across it,
    /// the walk turning at each line's far end. The disc is sized by bisection so the sweep's
    /// straight-line length — including the legs out to a disc that is not centred on the start
    /// — is the distance asked for, and `roadFactor` corrects for a real route being longer than
    /// the straight lines it follows.
    ///
    /// Returns `nil` when even a disc of no size cannot be reached and returned within the
    /// distance, which is what prunes a centre too far away to be worth walking to.
    private func tourLoopSweep(start: CLLocationCoordinate2D,
                               centre: CLLocationCoordinate2D,
                               bearing: Double,
                               rows: Int,
                               target: Double,
                               coverage: CoverageIndex,
                               jitters: [(along: Double, across: Double)])
    -> (waypoints: [CLLocationCoordinate2D], radius: Double)? {
        let radians = bearing * .pi / 180
        let along = (east: sin(radians), north: cos(radians))
        let across = (east: cos(radians), north: -sin(radians))

        func rowLines(of radius: Double) -> [[CLLocationCoordinate2D]] {
            let spacing = 2 * radius / Double(rows)
            return (0..<rows).map { row in
                let jitter = row < jitters.count ? jitters[row] : (along: 0, across: 0)
                let offset = -radius + (Double(row) + 0.5) * spacing + radius * jitter.across
                let half = max(1, (radius * radius - offset * offset).squareRoot())
                    * (1 + jitter.along)
                func point(_ t: Double) -> CLLocationCoordinate2D {
                    Geo.offset(centre,
                               east: t * along.east + offset * across.east,
                               north: t * along.north + offset * across.north)
                }
                return row.isMultiple(of: 2) ? [point(-half), point(half)] : [point(half), point(-half)]
            }
        }
        func chain(_ lines: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
            [start] + lines.flatMap { $0 } + [start]
        }

        let wanted = target / roadFactor
        // The disc has to hold the start: the user is somewhere inside the shape, not outside it
        // with a leg out to it and back. So the radius never drops below the distance from the
        // centre to the start, and a centre too far away to be reached and returned within the
        // distance — even with a disc of no size — is pruned here.
        let floor = CoverageIndex.meters(from: start, to: centre)
        var low = floor
        var high = max(floor + 1, target)
        guard CoverageIndex.length(of: chain(rowLines(of: high))) > wanted,
              CoverageIndex.length(of: chain(rowLines(of: low))) <= wanted else { return nil }
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if CoverageIndex.length(of: chain(rowLines(of: mid))) < wanted { low = mid } else { high = mid }
        }
        let radius = (low + high) / 2
        guard radius > 5 else { return nil }

        // Only the rows that still hold ground the user has not covered are walked.
        var swept: [CLLocationCoordinate2D] = []
        for row in rowLines(of: radius) where coverage.uncoveredMeters(of: row) >= config.tourRowMinNewMeters {
            swept.append(contentsOf: row.map {
                bias($0, across: bearing, span: radius * 0.25, coverage: coverage)
            })
        }
        guard !swept.isEmpty else { return nil }
        return (swept, radius)
    }

    /// A tour sweep of the corridor between the start and the destination: `rows` cross-cuts,
    /// alternating direction, from the start end to the destination end. Sized by bisection so
    /// its straight-line length is the distance asked for, and one-sided by `side` so the two
    /// alternatives are the two sides of the way there.
    private func tourCorridor(start: CLLocationCoordinate2D,
                              destination: CLLocationCoordinate2D,
                              rows: Int,
                              side: Double,
                              jitter: Double,
                              target: Double,
                              coverage: CoverageIndex,
                              client: DirectionsClient) async -> [DirectionsLeg]? {
        let corridor = Geo.bearing(from: start, to: destination) + jitter
        let radians = (corridor + side * 90) * .pi / 180
        let across = (east: cos(radians), north: -sin(radians))

        func rowLines(of reach: Double) -> [[CLLocationCoordinate2D]] {
            (0..<rows).map { row in
                let base = CoverageIndex.interpolate(start, destination,
                                                     (Double(row) + 0.5) / Double(rows))
                func point(_ lateral: Double) -> CLLocationCoordinate2D {
                    Geo.offset(base, east: lateral * across.east, north: lateral * across.north)
                }
                return row.isMultiple(of: 2) ? [point(-reach), point(reach)] : [point(reach), point(-reach)]
            }
        }
        func chain(_ lines: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
            [start] + lines.flatMap { $0 } + [destination]
        }

        let wanted = target / roadFactor
        var low = 0.0
        var high = max(200, target)
        guard CoverageIndex.length(of: chain(rowLines(of: high))) > wanted else { return nil }
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if CoverageIndex.length(of: chain(rowLines(of: mid))) < wanted { low = mid } else { high = mid }
        }
        let reach = (low + high) / 2
        guard reach > 5 else { return nil }

        var swept: [CLLocationCoordinate2D] = []
        for row in rowLines(of: reach) where coverage.uncoveredMeters(of: row) >= config.tourRowMinNewMeters {
            swept.append(contentsOf: row.map {
                bias($0, across: corridor, span: reach * 0.4, coverage: coverage)
            })
        }
        guard !swept.isEmpty else { return nil }

        let points = [start] + swept + [destination]
        let pairs = zip(points, points.dropFirst()).map { (from: $0, to: $1) }
        return await route(Array(pairs), client: client)
    }

    /// The share of the samples inside a disc that fall on ground no workout has covered. The
    /// measure of "is there anything here to find", which is what makes the tour prefer a
    /// half-explored neighbourhood over a fully walked one.
    private func tourDensity(centre: CLLocationCoordinate2D,
                             radius: Double,
                             coverage: CoverageIndex) -> Double {
        let samples = max(3, config.tourDensitySamples)
        var uncovered = 0
        var total = 0
        for i in 0..<samples {
            for j in 0..<samples {
                let x = (Double(i) + 0.5) / Double(samples) * 2 - 1
                let y = (Double(j) + 0.5) / Double(samples) * 2 - 1
                guard x * x + y * y <= 1 else { continue }
                total += 1
                if !coverage.isCovered(Geo.offset(centre, east: x * radius, north: y * radius)) {
                    uncovered += 1
                }
            }
        }
        return total > 0 ? Double(uncovered) / Double(total) : 0
    }

    /// How far, on average by length, a polyline runs from a point. The tour is docked on it, so
    /// a route that fills the streets under the user beats one that goes the same distance out
    /// to an emptier corner.
    private func meanDistance(from origin: CLLocationCoordinate2D,
                              along coordinates: [CLLocationCoordinate2D]) -> Double {
        var weighted = 0.0
        var total = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let segment = CoverageIndex.meters(from: a, to: b)
            let mid = CoverageIndex.interpolate(a, b, 0.5)
            weighted += CoverageIndex.meters(from: origin, to: mid) * segment
            total += segment
        }
        return total > 0 ? weighted / total : 0
    }

    // MARK: - Legs

    /// Routes a list of point-to-point legs, a few at a time, and returns them in order — or
    /// `nil` if any one of them failed, since a route with a hole in it is not a route.
    private func route(_ pairs: [(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)],
                       client: DirectionsClient) async -> [DirectionsLeg]? {
        guard !pairs.isEmpty else { return [] }
        let limit = max(1, config.maxConcurrentLegs)
        var results = [DirectionsLeg?](repeating: nil, count: pairs.count)

        await withTaskGroup(of: (Int, DirectionsLeg?).self) { group in
            var next = 0
            func addNext() {
                guard next < pairs.count else { return }
                let index = next
                next += 1
                let pair = pairs[index]
                group.addTask { (index, await RoutePlanner.leg(from: pair.from, to: pair.to,
                                                               client: client)) }
            }
            for _ in 0..<min(limit, pairs.count) { addNext() }
            for await (index, leg) in group {
                results[index] = leg
                addNext()
            }
        }

        guard results.allSatisfy({ $0 != nil }) else { return nil }
        return results.compactMap { $0 }
    }

    /// One leg, retried a couple of times when the service asks us to slow down.
    private static func leg(from: CLLocationCoordinate2D,
                            to: CLLocationCoordinate2D,
                            client: DirectionsClient) async -> DirectionsLeg? {
        for attempt in 0..<3 {
            do {
                let legs = try await client.route(from: from, to: to)
                guard let first = legs.first, first.coordinates.count > 1 else { return nil }
                return first
            } catch DirectionsError.throttled {
                try? await Task.sleep(for: .milliseconds(400 << attempt))
            } catch {
                return nil
            }
        }
        return nil
    }

    // MARK: - Scoring

    private func makeRoute(id: Int, legs: [DirectionsLeg], coverage: CoverageIndex) -> PlannedRoute? {
        let coordinates = Geo.stitch(legs.map(\.coordinates))
        guard coordinates.count > 1 else { return nil }
        let reported = legs.reduce(0) { $0 + $1.distance }
        return PlannedRoute(id: id,
                            coordinates: coordinates,
                            distance: reported > 0 ? reported : CoverageIndex.length(of: coordinates),
                            travelTime: legs.reduce(0) { $0 + $1.travelTime },
                            uncoveredMeters: coverage.uncoveredMeters(of: coordinates))
    }

    /// Ranks the routed candidates, keeps the best few, and numbers them so 0 is the primary.
    private func finalize(request: PlanRequest,
                          start: CLLocationCoordinate2D,
                          routes: [PlannedRoute],
                          history: PlanHistory,
                          coverage: CoverageIndex,
                          tour: Bool = false) -> RoutePlan? {
        let target = max(200, request.targetMeters)
        var scored: [(route: PlannedRoute, score: Double)] = []
        for route in routes {
            let fit = 1 - min(1, abs(route.distance - target) / target)
            let within = abs(route.distance - target) <= target * config.distanceTolerance
            let midpoint = Geo.pointAlong(route.coordinates, fraction: 0.5) ?? start
            let penalty = history.penalty(start: start,
                                          bearing: Geo.bearing(from: start, to: midpoint),
                                          meters: target, config: config)
            // The variation comes from which shapes were generated and routed, not from noise
            // here: this is the last word on which route the user is offered first, and it
            // should be the best of them rather than the luckiest.
            let shortfall = max(0, minimumNew - route.newFraction)
            let backtrack = route.distance > 0
                ? coverage.selfOverlapMeters(of: route.coordinates) / route.distance : 0
            let nearness = tour
                ? min(1, meanDistance(from: start, along: route.coordinates) / target) : 0
            let score = 0.5 * route.newFraction + 0.3 * fit - penalty
                - 3 * shortfall - (within ? 0 : 2)
                - config.backtrackPenalty * backtrack
                - config.tourCentrePenalty * nearness
            scored.append((route, score))
        }
        let limit = max(1, min(routeCount, config.maxLegsPerRoute))
        let ordered = scored.sorted { $0.score > $1.score }.prefix(limit)
        let numbered = ordered.enumerated().map { offset, element in
            PlannedRoute(id: offset,
                         coordinates: element.route.coordinates,
                         distance: element.route.distance,
                         travelTime: element.route.travelTime,
                         uncoveredMeters: element.route.uncoveredMeters)
        }
        guard !numbered.isEmpty else { return nil }
        return RoutePlan(request: request, start: start, routes: Array(numbered))
    }

    private func record(_ plan: RoutePlan?, start: CLLocationCoordinate2D, request: PlanRequest) {
        guard let primary = plan?.primary,
              let midpoint = Geo.pointAlong(primary.coordinates, fraction: 0.5) else { return }
        var history = PlanHistory.load()
        history.record(start: start,
                       bearing: Geo.bearing(from: start, to: midpoint),
                       meters: max(200, request.targetMeters))
        history.save()
    }
}

/// A small, seedable generator, so a plan can be reproduced from its seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The walks the explorer has recently suggested from somewhere near here, kept between
/// launches, so the same start and distance do not keep producing the same route.
struct PlanHistory {
    struct Entry: Codable {
        var latitude: Double
        var longitude: Double
        var bearing: Double
        var meters: Double
    }

    private static let key = "explorePlanHistory"
    private static let limit = 12
    /// How close a start has to be for a past plan to count as "from here".
    private static let nearbyMeters: Double = 60
    /// How close the distance has to be, as a share of the requested one.
    private static let similarDistance = 0.3

    private var entries: [Entry] = []

    static func load() -> PlanHistory {
        var history = PlanHistory()
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return history }
        history.entries = decoded
        return history
    }

    /// How much a candidate should be docked for repeating a recent plan's direction.
    func penalty(start: CLLocationCoordinate2D,
                 bearing: Double,
                 meters: Double,
                 config: RoutePlanner.Config) -> Double {
        var worst = 0.0
        for entry in entries {
            let entryStart = CLLocationCoordinate2D(latitude: entry.latitude,
                                                    longitude: entry.longitude)
            guard CoverageIndex.meters(from: entryStart, to: start) < Self.nearbyMeters else { continue }
            guard abs(entry.meters - meters) <= meters * Self.similarDistance else { continue }
            let delta = abs(((bearing - entry.bearing + 540).truncatingRemainder(dividingBy: 360)) - 180)
            let closeness = max(0, 1 - delta / config.recencyWindowDegrees)
            worst = max(worst, closeness * config.recencyPenalty)
        }
        return worst
    }

    mutating func record(start: CLLocationCoordinate2D, bearing: Double, meters: Double) {
        entries.append(Entry(latitude: start.latitude, longitude: start.longitude,
                             bearing: bearing, meters: meters))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
