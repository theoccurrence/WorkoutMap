import Foundation
import CoreLocation

/// Plans a walk that covers as much ground as possible the user has never covered.
///
/// Both shapes are a zigzag sized so its straight-line length is the distance asked for, and the
/// setting that matters here is how many legs that zigzag is made of: a few long ones reach far
/// out, many short ones fill the streets around the route instead. The distance is therefore
/// held roughly constant while the *shape* changes, which is the whole point of the setting.
///
/// * **loop** — a zigzag over a square centred on the start, the route turning at each row's far
///   end and coming home. Two rows is a long bow out and back around the start; five is a
///   lawnmower over the streets right around it.
/// * **destination** — a zigzag along the direct line, alternating either side of it. One
///   excursion is the big bow off the corridor; five are side streets either side of the way
///   there.
///
/// `MKDirections` knows no waypoints, so every shape is a handful of point-to-point legs stitched
/// into one polyline. Candidates are scored against the coverage grid *before* anything is
/// routed, so only the best few ever reach the service.
struct RoutePlanner {
    struct Config {
        /// How many shapes are scored before any network request, at the start itself.
        var candidates = 12
        /// And how many more on rings around it — the ground under the user's feet is the ground
        /// they have covered most, so a loop that only ever centres there can never be mostly
        /// new. Each factor is a share of the radius a circle of the requested length would have.
        var ringFactors: [Double] = [0.45, 0.9, 1.4, 2.0]
        var ringBearings = 6
        /// How many `MKDirections` calls run at once — the service throttles a burst
        /// (`MKError.Code.loadingThrottled`). The plan's `DirectionsPacer` meters the rate on
        /// top of this, and a leg that is refused is asked for again rather than drawn as a line.
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
        /// How much a route is docked for walking the same street twice. The share of the route
        /// that doubles back is multiplied by this. A dead end is the one time a double-back is
        /// unavoidable, so the share it produces is small enough that the route is still ranked
        /// ahead of a genuinely worse one.
        var backtrackingPenalty = 3.0
        /// How close two points have to be to count as the same street, in metres.
        var backtrackingSameStreetMeters = 25.0
        /// How far apart along the route two visits have to be, in metres, so a turn is not a
        /// double-back.
        var backtrackingMinGapMeters = 40.0
        /// How much the direction of travel may differ and still count as the same street:
        /// straight on or straight back, within this many degrees.
        var backtrackingBearingTolerance = 45.0
        /// How much of the route's start and end to ignore, so a loop closing at its start is
        /// not mistaken for a double-back.
        var backtrackingEndMeters = 30.0
        /// The most legs one route may be made of, and the most a whole plan may cost. The
        /// second is the ceiling the settings' own maximums ask for — five routes of five legs —
        /// plus a little slack, so asking for five routes never silently yields three. What
        /// keeps a burst from being throttled is `maxConcurrentLegs`, the plan's `DirectionsPacer`
        /// and the retries, not this.
        var maxLegsPerRoute = 8
        /// A fill spends one request per waypoint, and a fill's waypoints are not the polygon's
        /// legs — twelve of them is normal. The plan budget therefore has to cover a few whole
        /// fills, not just a few polygons: sixty requests at three concurrent is twenty batches,
        /// which the service serves without throttling.
        var maxLegsPerPlan = 60

        /// The number of legs a loop asks for. Tight means "fill the streets around here" rather
        /// than "walk a big circle": on the map the triangle's long legs between far-apart
        /// vertices are what the routing service cuts across, so a triangle reads as a big circle
        /// and a many-sided polygon reads as a compact fill. Tight is therefore the triangle and
        /// wide is the octagon — the opposite of what the vertex count alone suggests.
        static func loopSteps(for shape: Double) -> Int {
            8 - Int((min(max(shape, 0), 1) * 5).rounded())
        }

        /// The number of legs a start-to-destination route asks for. Tight means "do not wander
        /// off the direct line", so a tight route is a gentle zigzag with many waypoints close to
        /// the line; wide is one waypoint far to the side, which is the most a detour can bulge.
        static func destinationSteps(for shape: Double) -> Int {
            1 + Int((min(max(shape, 0), 1) * 4).rounded())
        }
    }

    var config = Config()
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
        switch request.mode {
        case .loop:
            return await planLoop(request: request, start: start, coverage: coverage, client: client)
        case .destination:
            return await planDestination(request: request, start: start, coverage: coverage, client: client)
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
        // Three legs is the floor: two legs is a line, and a line is walked out and back along
        // the same street. A closed polygon needs at least a triangle, and its two legs at the
        // start leave in different directions, so the walk cannot double back on itself there.
        let steps = max(3, min(config.maxLegsPerRoute,
                               Config.loopSteps(for: max(shape, minimumNew))))

        // Tight is a different kind of walk, not a tighter polygon: a greedy fill that at every
        // step prefers the least covered ground within reach of where it stands. A polygon walks
        // a circle around the neighbourhood; this walks the neighbourhood itself, street by
        // street, and doubles back only when there is nothing new left to reach. Wide keeps the
        // polygon, which is the "big arc" the setting asks for.
        let greedy = shape >= 0.5

        let bearings = loopBearings(generator: &generator)
        var candidates: [(waypoints: [CLLocationCoordinate2D], rough: Double)] = []
        for (index, bearing) in bearings.enumerated() {
            // A little wobble on every turning point, so two shapes that set off the same way are
            // still not the same walk.
            let jitters = (0..<steps).map { _ in
                (along: Double.random(in: -0.16...0.16, using: &generator),
                 across: Double.random(in: -0.16...0.16, using: &generator))
            }
            var waypoints: [CLLocationCoordinate2D]?
            var filled = false
            if greedy {
                // A fill's routed length is 1.6 to 3.1 times its straight-line length, depending
                // on how much it wanders, so no single budget hits the distance asked for. Spread
                // the budgets across the candidates and let the final ranking — which measures the
                // routed distance — pick the one that lands closest.
                let spread = Double(index) / Double(max(1, bearings.count - 1))
                // A routed fill in a street grid runs 1.6 to 2.2 times its straight length, so the
                // straight budget is a bit over half the target — enough to land near the distance
                // asked for without the walk running out of ground and stopping short.
                let fillBudget = target * (0.40 + 0.25 * spread)
                // The waypoint count is what the plan's request budget can afford: one request
                // per waypoint, split across the candidates that will actually be routed. A
                // candidate costs one leg more than it has waypoints — the walk home from its
                // last one — so the share has to leave that leg room, or every candidate of a
                // one-route plan is a waypoint too long for the budget and never gets routed.
                let perCandidate = max(4, config.maxLegsPerPlan / max(1, routeCount) - 1)
                waypoints = coverageWalk(start: start, wanted: fillBudget, maxSteps: perCandidate,
                                         coverage: coverage, generator: &generator)
                filled = waypoints != nil
            }
            // A fill that boxes itself in still has to offer a route: a long walk in a dense grid
            // runs out of gaps, and a spinner is worse than the polygon the wide setting uses.
            if waypoints == nil {
                waypoints = loopShape(start: start, bearing: bearing, steps: steps,
                                      target: target, roadFactor: roadFactor,
                                      jitters: jitters)
            }
            guard let waypoints, !waypoints.isEmpty else { continue }

            let straight = [start] + waypoints + [start]
            let length: Double = max(1, CoverageIndex.length(of: straight))
            let uncovered: Double = coverage.uncoveredMeters(of: straight)
            let fraction: Double = uncovered / length
            // A fill's straight length is not the distance that matters — its routed length is —
            // and a routed fill is about 2.2 times its straight length. Estimating the routed
            // length keeps the fit term meaningful, so a fill that lands short of the target does
            // not outrank one that lands on it just because it happened to cover more streets.
            let measured = length * 1.3
            let fit: Double = 1 - min(1, abs(measured - target) / target)
            let penalty: Double = history.penalty(start: start, bearing: bearing,
                                                  meters: target, config: config)
            let shortfall: Double = max(0, minimumNew - fraction)
            let noise: Double = Double.random(in: -1...1, using: &generator)
            // A fill that lands on the distance is worth more than a slightly denser one that
            // lands 25% short, so its fit term carries more weight than a polygon's.
            let fitWeight = filled ? 0.6 : 0.3
            let rough: Double = fraction + fitWeight * fit - penalty - 3 * shortfall
                + config.noise * noise
            candidates.append((waypoints, rough))
        }

        // Route more candidates than the settings ask for, so the final ranking has a real choice
        // and can reject a shape that doubles back on itself. Three is the floor when only one
        // route is asked for: one candidate leaves no alternative to prefer. The leg count is
        // capped by the plan's request budget, because a fill costs one request per waypoint and
        // a burst the service refuses drops the whole candidate — a long fill that asks for two
        // hundred requests yields nothing at all.
        let ranked = candidates.sorted { $0.rough > $1.rough }
        let wanted = max(1, min(ranked.count, max(routeCount * 2, 3)))
        let pacer = DirectionsPacer()
        // Only a candidate the service routed end to end becomes one of the routes the user is
        // offered. One it would not route end to end has a hole in it, and the line that used to
        // be drawn across that hole is what the user reads as a route through the houses — so the
        // candidate is dropped, and a plan that keeps none of them comes back empty-handed rather
        // than wrong. The map screen says so and offers to ask again.
        var routed: [PlannedRoute] = []
        var spent = 0
        for candidate in ranked.prefix(wanted) {
            guard !Task.isCancelled else { return nil }
            let cost = candidate.waypoints.count + 1
            guard spent + cost <= config.maxLegsPerPlan else { continue }
            spent += cost
            let points = [start] + candidate.waypoints + [start]
            let pairs = Array(zip(points, points.dropFirst()).map { (from: $0, to: $1) })
            let legs = await route(pairs, client: client, pacer: pacer)
            if let made = makeRoute(id: routed.count, legs: legs, coverage: coverage) {
                routed.append(made)
            }
        }
        guard !routed.isEmpty else { return nil }

        let plan = finalize(request: request, start: start, routes: routed, history: history)
        record(plan, start: start, request: request)
        return plan
    }

    /// The directions a loop's polygon is tried in. A polygon's centre is fixed by the start and
    /// the bearing — it sits one circumradius away — so the only free choice is which way the
    /// first leg leaves the start. Spreading that around the compass is what keeps the same
    /// request from returning the same walk.
    private func loopBearings(generator: inout SplitMix64) -> [Double] {
        var bearings: [Double] = []
        for index in 0..<config.candidates {
            let base = Double(index) / Double(config.candidates) * 360
            bearings.append((base + Double.random(in: -22...22, using: &generator))
                .truncatingRemainder(dividingBy: 360))
        }
        for _ in config.ringFactors {
            for index in 0..<config.ringBearings {
                let base = Double(index) / Double(config.ringBearings) * 360
                bearings.append((base + Double.random(in: -18...18, using: &generator))
                    .truncatingRemainder(dividingBy: 360))
            }
        }
        return bearings
    }

    /// A loop as a closed polygon: `steps` vertices on a circle, the start as one of them. The
    /// route runs start → v1 → … → v(steps-1) → start, so the first and last legs are two
    /// different edges of the polygon and leave the start at the polygon's interior angle
    /// (60° for a triangle, 108° for a pentagon). That is the whole point of the shape: a walk
    /// cannot set off up a street and come straight back down it, because the way out and the
    /// way home are not the same direction.
    ///
    /// The polygon is sized so its perimeter is the distance asked for, corrected for a real
    /// route being longer than the straight lines it follows. `steps` is the number of legs.
    ///
    /// Returns `nil` when the polygon would be too small to be a walk at all.
    private func loopShape(start: CLLocationCoordinate2D,
                           bearing: Double,
                           steps: Int,
                           target: Double,
                           roadFactor: Double,
                           jitters: [(along: Double, across: Double)]) -> [CLLocationCoordinate2D]? {
        let perimeter = target / roadFactor
        let scale = perimeter / (Double(steps) * 2 * sin(.pi / Double(steps)))
        guard scale > 1 else { return nil }
        // The centre sits one circumradius from the start, in the direction the first leg leaves.
        let centre = Geo.destination(from: start, bearing: bearing, distance: scale)
        let startAngle = bearing + 180
        return (1..<steps).map { index in
            let jitter = index < jitters.count ? jitters[index] : (along: 0, across: 0)
            let radius = scale * (1 + jitter.along)
            let angle = startAngle + Double(index) * 360 / Double(steps)
                + atan(jitter.across) * 180 / .pi
            return Geo.destination(from: centre, bearing: angle, distance: radius)
        }
    }

    /// A greedy fill: at every step, look at a ring of points within reach of where the walk
    /// stands and move to the one whose surroundings are least covered. That is what "tight"
    /// means — cover the streets around here, not walk a circle around the neighbourhood. The
    /// walk only doubles back when there is nothing new left to reach, and it steers home over
    /// the last quarter so the loop closes without a long straight return leg.
    ///
    /// Returns `nil` when it cannot take a single step, which is what prunes a start boxed in by
    /// covered ground.
    private func coverageWalk(start: CLLocationCoordinate2D,
                              wanted: Double,
                              maxSteps: Int,
                              coverage: CoverageIndex,
                              generator: inout SplitMix64,
                              towards end: CLLocationCoordinate2D? = nil) -> [CLLocationCoordinate2D]? {
        let ringSamples = 24
        // Every waypoint is one `MKDirections` request, and the service throttles a burst: a
        // 20 km fill at 95 m steps asked for 160 requests per candidate and every candidate was
        // dropped when the service pushed back. The waypoint count therefore comes from the leg
        // budget, and the step length grows with the distance so the walk still covers it.
        let stepMeters = max(95, wanted / Double(max(1, maxSteps)))
        // The radius grows with the distance but sub-linearly, so a long fill spreads over a
        // wider neighbourhood instead of running down one corridor and back.
        let maxRadius = min(3000, max(350, wanted * 0.28))
        let minGap = 42.0

        // Where the walk's last quarter steers: back to where it started, which closes a loop, or
        // on to the next row's ground, which is what makes a ladder march instead of circling.
        let home = end ?? start

        var waypoints: [CLLocationCoordinate2D] = []
        var current = start
        var visited: [CLLocationCoordinate2D] = [start]
        var accumulated = 0.0
        var previousBearing: Double? = nil

        for _ in 0..<maxSteps {
            let remaining = wanted - accumulated
            guard remaining > 0 else { break }
            let progress = accumulated / wanted
            // The walk spirals: it fills outward until most of the distance is walked, then steers
            // home. Without the growing cap it wanders off in one direction and never comes back,
            // which is the band the first version produced.
            let radiusTarget = maxRadius * max(0.3, min(1, progress / 0.45))
            // The walk only starts steering home in the last quarter. Steering earlier turns the
            // second half of a long walk into one long arc back to the start — the exact "big
            // detour" the tight mode is supposed to avoid. The last quarter is enough to close
            // the loop without retracing.
            let homeBias = max(0, (progress - 0.75) / 0.25)

            // Constraints are relaxed step by step when the walk is boxed in: a fill that gives up
            // at the first covered corner is worse than one that backs out and keeps going.
            var best: (point: CLLocationCoordinate2D, score: Double)? = nil
            for relax in 0..<4 {
                let gap = minGap * pow(0.5, Double(relax))
                let reach = radiusTarget * (1 + Double(relax) * 0.5)

                for index in 0..<ringSamples {
                    let angle = (Double(index) / Double(ringSamples) * 360
                        + Double.random(in: -6...6, using: &generator))
                        .truncatingRemainder(dividingBy: 360)
                    let candidate = Geo.destination(from: current, bearing: angle, distance: stepMeters)

                    let radius = CoverageIndex.meters(from: start, to: candidate)
                    guard radius <= reach else { continue }

                    let nearest = visited.map { CoverageIndex.meters(from: $0, to: candidate) }.min() ?? 0
                    guard nearest >= gap else { continue }

                    let uncovered = 1 - coverage.coveredAround(candidate)
                    // In a fresh area the user's history is empty, so `uncovered` is 1 for every
                    // candidate and the score would be a coin flip. The walk's own path is the
                    // coverage that matters here: a candidate far from everything it has already
                    // walked is ground it has not covered, and that is what "tight" means.
                    let selfGap = min(1, nearest / max(1, stepMeters * 2))
                    var turnPenalty = 0.0
                    if let previousBearing {
                        let delta = abs(angle - previousBearing)
                        let turn = min(delta, 360 - delta)
                        if turn > 130 { turnPenalty = 0.4 }
                    }
                    let homeTurn = abs(angle - Geo.bearing(from: candidate, to: home))
                    let homeScore = homeBias * (1 - min(1, min(homeTurn, 360 - homeTurn) / 180))

                    // New ground dominates: "tight" is about walking streets the route has not
                    // walked, not about keeping distance from the last waypoint.
                    let score = 0.45 * uncovered + 0.35 * selfGap + 0.2 * homeScore - turnPenalty

                    if best == nil || score > best!.score {
                        best = (candidate, score)
                    }
                }
                if best != nil { break }
            }

            // Boxed in: keep the waypoints already collected. A fill that covers part of the
            // ground is a route; throwing them away leaves the user with a spinner.
            guard let best else { break }
            waypoints.append(best.point)
            // The walk claims the ground it crosses, not just the points it stops at. Without
            // this it happily picks a next waypoint that sends the route back along the street it
            // just walked, because the coverage grid only knows about the user's history — not
            // about the route being built right now. That is the long out-and-back this mode
            // exists to avoid.
            let claimed = CoverageIndex.samples(from: current, to: best.point, every: 20)
            visited.append(contentsOf: claimed)
            accumulated += CoverageIndex.meters(from: current, to: best.point)
            previousBearing = Geo.bearing(from: current, to: best.point)
            current = best.point
        }

        return waypoints.isEmpty ? nil : waypoints
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

    /// Plans a walk from the start to a destination that is longer than the way there.
    ///
    /// The corridor fixes what shapes are available: a walk that has to end somewhere else cannot
    /// circle a point the way a loop circles home, so a candidate here is a **chain of waypoints
    /// from the start to the destination** and the setting picks which kind of chain
    /// (see `destinationCandidates`). What surrounds them is the loop's own pipeline — and that is
    /// the point: it is the pipeline, not the polygon, that makes the loop behave. Candidates are
    /// scored against the coverage grid *before* anything is routed, the best few are routed
    /// patiently, and the ranking keeps the ones that came back whole and land closest to the
    /// distance asked for.
    private func planDestination(request: PlanRequest,
                                 start: CLLocationCoordinate2D,
                                 coverage: CoverageIndex,
                                 client: DirectionsClient) async -> RoutePlan? {
        guard let destination = request.destination,
              !Geo.same(start, destination) else { return nil }
        let target = max(200, request.targetMeters)
        let history = PlanHistory.load()

        let pacer = DirectionsPacer()
        let directPair = (from: start, to: destination)
        // The way there is asked for as patiently as any other leg. It used to be a single
        // request whose refusal ended the plan in a spinner — and it is the one route the user
        // measures every other one against.
        var directLegs = await Self.request(from: start, to: destination, client: client,
                                            pacer: pacer, attempts: Self.legAttempts)
        if directLegs.isEmpty,
           let halved = await split(directPair, client: client, pacer: pacer,
                                    depth: Self.splitDepth) {
            directLegs = [halved]
        }
        guard let direct = directLegs.first else { return nil }

        // The way there is a route like any other and it is already routed, so it goes into the
        // ranking as it is: offered last — or not at all — when the user asked for a walk, and
        // offered first when they asked for barely more than the walk there.
        var routed: [PlannedRoute] = []
        if let made = makeRoute(id: 0, legs: [direct], coverage: coverage) { routed.append(made) }

        if target > direct.distance * 1.05 {
            var generator = SplitMix64(seed: seed &+ 1)
            let candidates = destinationCandidates(start: start, destination: destination,
                                                   direct: direct.distance, target: target,
                                                   coverage: coverage, history: history,
                                                   generator: &generator)
            // As in a loop: more candidates than the settings ask for, so the ranking has a real
            // choice, and the plan's request budget spent on the ones the pre-score liked.
            let ranked = candidates.sorted { $0.rough > $1.rough }
            let wanted = max(1, min(ranked.count, max(routeCount * 2, 3)))
            var spent = 0
            for candidate in ranked.prefix(wanted) {
                guard !Task.isCancelled else { return nil }
                let cost = candidate.waypoints.count + 1
                guard spent + cost <= config.maxLegsPerPlan else { continue }
                spent += cost
                let points = [start] + candidate.waypoints + [destination]
                let pairs = Array(zip(points, points.dropFirst()).map { (from: $0, to: $1) })
                let legs = await route(pairs, client: client, pacer: pacer)
                if let made = makeRoute(id: routed.count, legs: legs, coverage: coverage) {
                    routed.append(made)
                }
            }
        } else {
            // Barely longer than the way there: there is no shape to build, and the service's own
            // alternates for that leg are the whole answer.
            for leg in directLegs.dropFirst().prefix(2) {
                if let made = makeRoute(id: routed.count, legs: [leg], coverage: coverage) {
                    routed.append(made)
                }
            }
        }

        guard !routed.isEmpty else { return nil }
        let plan = finalize(request: request, start: start, routes: routed, history: history)
        record(plan, start: start, request: request)
        return plan
    }

    /// The chains a destination plan is made of, before anything is routed — each with the same
    /// noisy pre-score a loop's candidate carries: how much of the chain is ground the user has
    /// never covered, how close its estimated walking distance lands to the distance asked for,
    /// and what a recent plan from here already went for.
    ///
    /// Three families, and the *Route Shape* setting picks between them the way it does in a loop:
    ///
    /// * **zigzag** — the way there, taken in a few legs that alternate either side of it. *Wide*
    ///   puts a single waypoint far out to the side, *tight* marches more of them closer to the
    ///   line. This is the shape that keeps to the corridor, and the only one that is any use when
    ///   the distance asked for is barely more than the way there.
    /// * **lollipop** — out to a point along the way there, the loop's own greedy fill hung on that
    ///   point, then the last leg to the destination. The fill comes back to its anchor, which is
    ///   what makes it a loop rather than a drift to one side.
    /// * **ladder** — the same greedy fill, hung on several points along the corridor and
    ///   alternating sides, so the walk sweeps the streets either side of the way there instead of
    ///   circling one spot. This is the destination's answer to *tight*: the loop's own tight walk,
    ///   aimed at the destination rather than back at the start.
    ///
    /// Which of the three a candidate is comes from the setting — the ladder takes over as it
    /// tightens, the other two share what is left — and from how much further than the way there
    /// the user wants to walk, since a fill can only add what fits on the corridor.
    private func destinationCandidates(start: CLLocationCoordinate2D,
                                       destination: CLLocationCoordinate2D,
                                       direct: Double,
                                       target: Double,
                                       coverage: CoverageIndex,
                                       history: PlanHistory,
                                       generator: inout SplitMix64)
        -> [(waypoints: [CLLocationCoordinate2D], rough: Double)] {
        // The tighter of the two settings, as in a loop: a plan for a lot of new ground fills the
        // streets around the way there whatever the shape setting says, because that is where the
        // new ground is.
        let tightness = min(1, max(0, max(shape, minimumNew)))
        // What the wandering has to add, in straight-line metres. The corridor legs walk about as
        // long as they measure and the wandering is what the road factor is for, so this is the
        // same estimate the candidates are scored on below.
        let extra = max(0, target - direct) / roadFactor
        let fillable = extra > direct * 0.2
        // One request per waypoint, and one more for the leg to the destination; the plan's budget
        // is spread over the candidates that will actually be routed.
        let steps = max(3, config.maxLegsPerPlan / max(1, routeCount) - 1)
        let rows = max(2, min(6, steps / 5))

        var candidates: [(waypoints: [CLLocationCoordinate2D], rough: Double)] = []
        for index in 0..<config.candidates {
            let spread = Double(index) / Double(max(1, config.candidates - 1))
            // How far this candidate aims: a routed shape runs further than its straight lines and
            // no single ideal size knows how much, so the sizes are spread across the candidates
            // and the ranking keeps the one that lands on the distance asked for.
            let wanted = direct + extra * (0.75 + 0.5 * spread)
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0

            var waypoints: [CLLocationCoordinate2D]?
            if fillable, spread < tightness {
                waypoints = ladderWaypoints(start: start, destination: destination, rows: rows,
                                            wanted: wanted - direct, steps: steps,
                                            coverage: coverage, generator: &generator)
            } else if fillable, index.isMultiple(of: 2) == false {
                waypoints = lollipopWaypoints(start: start, destination: destination,
                                              fraction: 0.3 + 0.4 * spread,
                                              wanted: wanted - direct, steps: steps,
                                              coverage: coverage, generator: &generator)
            }
            if waypoints == nil {
                waypoints = zigzagWaypoints(start: start, destination: destination,
                                            steps: Config.destinationSteps(for: tightness),
                                            side: side,
                                            jitter: Double.random(in: -12...12, using: &generator),
                                            wanted: wanted, coverage: coverage)
            }
            guard let waypoints, !waypoints.isEmpty else { continue }

            let chain = [start] + waypoints + [destination]
            let length = max(1, CoverageIndex.length(of: chain))
            let uncovered = coverage.uncoveredMeters(of: chain)
            let fraction = uncovered / length
            let measured = direct + (length - direct) * roadFactor
            let fit = 1 - min(1, abs(measured - target) / target)
            let midpoint = Geo.pointAlong(chain, fraction: 0.5) ?? destination
            let penalty = history.penalty(start: start,
                                          bearing: Geo.bearing(from: start, to: midpoint),
                                          meters: target, config: config)
            let shortfall = max(0, minimumNew - fraction)
            let noise = Double.random(in: -1...1, using: &generator)
            let rough = fraction + 0.5 * fit - penalty - 3 * shortfall + config.noise * noise
            candidates.append((waypoints, rough))
        }
        return candidates
    }

    /// A zigzag candidate: the way there in `steps` legs, alternating either side of the straight
    /// line between start and destination, at the reach whose straight-line length is the length
    /// this candidate aims at.
    private func zigzagWaypoints(start: CLLocationCoordinate2D,
                                 destination: CLLocationCoordinate2D,
                                 steps: Int,
                                 side: Double,
                                 jitter: Double,
                                 wanted: Double,
                                 coverage: CoverageIndex) -> [CLLocationCoordinate2D] {
        let reach = zigzagReach(start: start, destination: destination, steps: steps, side: side,
                                wanted: wanted)
        return destinationShape(start: start, destination: destination, steps: steps, side: side,
                                jitter: jitter, offset: reach, coverage: coverage)
    }

    /// A lollipop candidate's waypoints: the loop's greedy fill, hung on a point along the way
    /// there. The fill ends where it started, near that point, so the leg out and the leg on to
    /// the destination are the stick the candy sits on.
    private func lollipopWaypoints(start: CLLocationCoordinate2D,
                                   destination: CLLocationCoordinate2D,
                                   fraction: Double,
                                   wanted: Double,
                                   steps: Int,
                                   coverage: CoverageIndex,
                                   generator: inout SplitMix64) -> [CLLocationCoordinate2D]? {
        let anchor = CoverageIndex.interpolate(start, destination, fraction)
        return coverageWalk(start: anchor, wanted: max(150, wanted), maxSteps: steps,
                            coverage: coverage, generator: &generator)
    }

    /// A ladder candidate's waypoints: the same greedy fill, hung on `rows` points along the way
    /// there and alternating sides, so the walk sweeps the streets either side of the corridor
    /// instead of circling one spot. The legs between one row's fill and the next are its rungs.
    private func ladderWaypoints(start: CLLocationCoordinate2D,
                                 destination: CLLocationCoordinate2D,
                                 rows: Int,
                                 wanted: Double,
                                 steps: Int,
                                 coverage: CoverageIndex,
                                 generator: inout SplitMix64) -> [CLLocationCoordinate2D]? {
        let across = Geo.bearing(from: start, to: destination) + 90
        // How far off the corridor a row sits: far enough to be off the corridor's own street,
        // and no further than the ground the row's fill has to cover allows.
        let offset = min(600, max(150, wanted * 0.2))
        let perRow = max(3, steps / rows)

        // Every row is aimed at the next one rather than back at itself: a row that came home
        // would walk its own streets twice, and the ladder's whole point is to march along the
        // corridor. The last row's way home is the destination.
        let anchors = (1...rows).map { row in
            CoverageIndex.interpolate(start, destination, Double(row) / Double(rows + 1))
        } + [destination]

        var waypoints: [CLLocationCoordinate2D] = []
        for row in 0..<rows {
            let side = row.isMultiple(of: 2) ? 1.0 : -1.0
            let anchor = Geo.destination(from: anchors[row], bearing: across, distance: offset * side)
            guard let fill = coverageWalk(start: anchor, wanted: max(120, wanted / Double(rows)),
                                          maxSteps: perRow, coverage: coverage,
                                          generator: &generator, towards: anchors[row + 1]) else {
                continue
            }
            waypoints.append(contentsOf: fill)
        }
        return waypoints.isEmpty ? nil : waypoints
    }

    /// The lateral reach whose *straight-line* zigzag is the length asked for. Bisection because
    /// the length is a sum of square roots and not linear in the reach.
    private func zigzagReach(start: CLLocationCoordinate2D,
                             destination: CLLocationCoordinate2D,
                             steps: Int,
                             side: Double,
                             wanted: Double) -> Double {
        func length(_ offset: Double) -> Double {
            CoverageIndex.length(of: [start]
                + destinationShape(start: start, destination: destination, steps: steps,
                                   side: side, jitter: 0, offset: offset, coverage: nil)
                + [destination])
        }
        var low = 0.0
        // A reach as long as the walk asked for is always further out than the walk itself needs
        // to be, since even a zigzag of one leg covers more than its lateral offset.
        var high = max(200, wanted)
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

    // MARK: - Legs

    /// One point-to-point request: where a leg leaves from, where it goes.
    private typealias LegPair = (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)

    /// How often a leg is asked for in the first pass, and in the passes that follow it.
    private static let legAttempts = 5
    private static let repeatAttempts = 3
    /// How many times a leg the service will not route in one piece is halved. Two is a quarter
    /// of the leg, which is inside what walking directions cover from anywhere a planned walk
    /// puts its waypoints.
    private static let splitDepth = 2
    /// Below this length, halving a leg buys nothing: the pieces are shorter than a street block,
    /// and a chord that short is a corner rather than a route across the houses.
    private static let splitFloorMeters = 60.0

    /// Routes a list of point-to-point legs and hands back one result per leg — `nil` where the
    /// service could not be made to answer at all.
    ///
    /// Three passes, because a leg that did not come back is almost always the service's own
    /// timing rather than the leg. The list patiently; then the legs it refused once more, after
    /// the rest of the plan has been through the service and the burst that caused the refusal
    /// is over; and then, for a leg the service will not route in one piece — throttled
    /// throughout, or farther than walking directions reach — in halves. What this replaces is
    /// the straight line between a refused leg's ends, which is how a plan used to come back
    /// with a route drawn across the houses it could not route.
    private func route(_ pairs: [LegPair],
                       client: DirectionsClient,
                       pacer: DirectionsPacer) async -> [DirectionsLeg?] {
        guard !pairs.isEmpty else { return [] }
        var results = await distributed(pairs, client: client, pacer: pacer,
                                        attempts: Self.legAttempts)

        var missing = results.indices.filter { results[$0] == nil }
        if !missing.isEmpty, !Task.isCancelled {
            await pacer.cool()
            let again = await distributed(missing.map { pairs[$0] }, client: client, pacer: pacer,
                                          attempts: Self.repeatAttempts)
            for (offset, leg) in again.enumerated() where leg != nil {
                results[missing[offset]] = leg
            }
            missing = results.indices.filter { results[$0] == nil }
        }

        for index in missing where !Task.isCancelled {
            results[index] = await split(pairs[index], client: client, pacer: pacer,
                                         depth: Self.splitDepth)
        }
        return results
    }

    /// One pass over a list of legs, `maxConcurrentLegs` of them in flight at a time. The pacer
    /// holds the rate back, so the whole pass asks no faster than the service wants to answer.
    private func distributed(_ pairs: [LegPair],
                             client: DirectionsClient,
                             pacer: DirectionsPacer,
                             attempts: Int) async -> [DirectionsLeg?] {
        guard !pairs.isEmpty else { return [] }
        let limit = max(1, config.maxConcurrentLegs)
        var results = [DirectionsLeg?](repeating: nil, count: pairs.count)

        await withTaskGroup(of: (Int, DirectionsLeg?).self) { group in
            var next = 0
            func addNext() {
                guard next < pairs.count, !Task.isCancelled else { return }
                let index = next
                next += 1
                let pair = pairs[index]
                group.addTask {
                    (index, await RoutePlanner.leg(from: pair.from, to: pair.to, client: client,
                                                   pacer: pacer, attempts: attempts))
                }
            }
            for _ in 0..<min(limit, pairs.count) { addNext() }
            for await (index, leg) in group {
                results[index] = leg
                addNext()
            }
        }
        return results
    }

    /// A leg the service will not route in one piece: half of it, then half of that. The middle
    /// point is on the straight line between the two ends, and the service snaps it to the
    /// nearest street, so the two halves are streets and their join is a junction. Returns `nil`
    /// when the halves refuse too — the caller's last resort is the chord this exists to avoid.
    private func split(_ pair: LegPair,
                       client: DirectionsClient,
                       pacer: DirectionsPacer,
                       depth: Int) async -> DirectionsLeg? {
        guard depth > 0,
              CoverageIndex.meters(from: pair.from, to: pair.to) > Self.splitFloorMeters else {
            return nil
        }
        let middle = CoverageIndex.interpolate(pair.from, pair.to, 0.5)
        var first = await Self.leg(from: pair.from, to: middle, client: client, pacer: pacer)
        if first == nil {
            first = await split((from: pair.from, to: middle), client: client, pacer: pacer,
                                depth: depth - 1)
        }
        var second = await Self.leg(from: middle, to: pair.to, client: client, pacer: pacer)
        if second == nil {
            second = await split((from: middle, to: pair.to), client: client, pacer: pacer,
                                 depth: depth - 1)
        }
        guard let first, let second else { return nil }
        return DirectionsLeg(coordinates: Geo.stitch([first.coordinates, second.coordinates]),
                             distance: first.distance + second.distance,
                             travelTime: first.travelTime + second.travelTime)
    }

    /// One leg, asked for as patiently as the plan can afford.
    private static func leg(from: CLLocationCoordinate2D,
                            to: CLLocationCoordinate2D,
                            client: DirectionsClient,
                            pacer: DirectionsPacer,
                            attempts: Int = RoutePlanner.legAttempts) async -> DirectionsLeg? {
        await request(from: from, to: to, client: client, pacer: pacer,
                      attempts: attempts).first
    }

    /// One request, asked for again and again while the service only pushes back, on the plan's
    /// pacer. Every route the service offers between the two points, or an empty list.
    ///
    /// A throttle is the service asking to be left alone for a moment, not an answer: the wait
    /// grows with every attempt, and the pacer widens it for the whole plan. Neither is an
    /// answer either, so a leg that is still refused after the last attempt comes back empty and
    /// the caller splits it rather than draw it.
    private static func request(from: CLLocationCoordinate2D,
                                to: CLLocationCoordinate2D,
                                client: DirectionsClient,
                                pacer: DirectionsPacer,
                                attempts: Int) async -> [DirectionsLeg] {
        for attempt in 1...max(1, attempts) {
            guard !Task.isCancelled else { return [] }
            await pacer.acquire()
            guard !Task.isCancelled else { return [] }
            let answer: Result<[DirectionsLeg], Error>
            do {
                answer = .success(try await client.route(from: from, to: to))
            } catch {
                answer = .failure(error)
            }

            switch answer {
            case .success(let legs):
                guard let first = legs.first, first.coordinates.count > 1 else { return [] }
                await pacer.succeeded()
                return legs
            case .failure(let error):
                if let refused = error as? DirectionsError {
                    // No walking route between these two points — usually a leg farther than
                    // walking directions reach. Asking again would not change the answer;
                    // splitting the leg is what does.
                    if case .noRoute = refused { return [] }
                    if case .throttled = refused { await pacer.throttled() }
                }
                guard attempt < attempts else { return [] }
                try? await Task.sleep(for: RoutePlanner.backoff(attempt))
            }
        }
        return []
    }

    /// How long a refused leg waits before it is asked for again: two seconds, then four, then
    /// eight — with a wobble, so the twenty legs of a fill that were throttled together do not
    /// come back in lockstep and get the plan throttled all over again. Seconds rather than
    /// milliseconds because the budget the service counts in is requests a **minute**: a retry a
    /// moment later is a retry from the same allowance.
    private static func backoff(_ attempt: Int) -> Duration {
        let seconds = min(8, pow(2, Double(attempt))) * Double.random(in: 0.75...1.25)
        return .milliseconds(Int(seconds * 1000))
    }

    // MARK: - Scoring

    /// Makes a route of the legs a candidate came back with — or `nil` when the service would not
    /// route one of them, because a route with a hole in it is not a route. The hole used to be
    /// filled with a straight line between the leg's ends, and that chord is what the user reads
    /// as a route drawn through the houses: a candidate the service would not route end to end is
    /// therefore dropped, and a plan that keeps none of them comes back empty-handed rather than
    /// wrong (`MapTabView` says so and offers to ask again).
    private func makeRoute(id: Int, legs: [DirectionsLeg?], coverage: CoverageIndex) -> PlannedRoute? {
        let routed = legs.compactMap { $0 }
        guard !routed.isEmpty, routed.count == legs.count else { return nil }
        let coordinates = Geo.stitch(routed.map(\.coordinates))
        guard coordinates.count > 1 else { return nil }
        let reported = Geo.length(routed)
        return PlannedRoute(id: id,
                            coordinates: coordinates,
                            distance: reported > 0 ? reported : CoverageIndex.length(of: coordinates),
                            travelTime: routed.reduce(0) { $0 + $1.travelTime },
                            uncoveredMeters: coverage.uncoveredMeters(of: coordinates))
    }

    /// Ranks the routed candidates, keeps the best few, and numbers them so 0 is the primary.
    private func finalize(request: PlanRequest,
                          start: CLLocationCoordinate2D,
                          routes: [PlannedRoute],
                          history: PlanHistory) -> RoutePlan? {
        let target = max(200, request.targetMeters)
        // A double-back is measured before scoring, so the routes that keep off their own ground
        // are ranked on their own. They are ranked *beside* the rest rather than instead of them,
        // though, and only while there are enough of them to fill the card: a walk that fills
        // streets at all comes back down one of them, so filtering the rest out outright is what
        // left a destination plan — whose shaped candidates are all fills — with nothing to offer
        // but the one candidate that never doubles back, the way the user has to walk anyway.
        let cleanLimit = 0.05
        var candidates: [(route: PlannedRoute, backtrack: Double)] = []
        for route in routes {
            let backtrack = Geo.backtrackingFraction(
                of: route.coordinates,
                sameStreetMeters: config.backtrackingSameStreetMeters,
                minGapMeters: config.backtrackingMinGapMeters,
                bearingTolerance: config.backtrackingBearingTolerance,
                endMeters: config.backtrackingEndMeters)
            candidates.append((route, backtrack))
        }
        let clean = candidates.filter { $0.backtrack <= cleanLimit }
        let pool = clean.count >= routeCount ? clean : candidates

        var scored: [(route: PlannedRoute, score: Double)] = []
        for (route, backtrack) in pool {
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
            // A tight fill is asked for a distance, so landing on it matters as much as the
            // streets it covers: a route 25% short is not the walk the user asked for. A wide
            // sweep is asked for a shape, so coverage still leads.
            let fitWeight = shape >= 0.5 ? 0.5 : 0.3
            let coverageWeight = shape >= 0.5 ? 0.45 : 0.5
            let score = coverageWeight * route.newFraction + fitWeight * fit - penalty
                - config.backtrackingPenalty * backtrack
                - 3 * shortfall - (within ? 0 : 2)
            scored.append((route, score))
        }
        let limit = max(1, min(routeCount, routes.count))
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
