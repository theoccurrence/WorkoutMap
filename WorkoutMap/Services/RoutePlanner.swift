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
        /// keeps a burst from being throttled is `maxConcurrentLegs` and the retry, not this.
        var maxLegsPerRoute = 8
        var maxLegsPerPlan = 30

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

        var candidates: [(waypoints: [CLLocationCoordinate2D], rough: Double)] = []
        for bearing in loopBearings(generator: &generator) {
            // A little wobble on every turning point, so two shapes that set off the same way are
            // still not the same walk.
            let jitters = (0..<steps).map { _ in
                (along: Double.random(in: -0.16...0.16, using: &generator),
                 across: Double.random(in: -0.16...0.16, using: &generator))
            }
            guard let waypoints = loopShape(start: start, bearing: bearing, steps: steps,
                                            target: target, roadFactor: roadFactor,
                                            jitters: jitters) else { continue }

            let straight = [start] + waypoints + [start]
            let length: Double = max(1, CoverageIndex.length(of: straight))
            let uncovered: Double = coverage.uncoveredMeters(of: straight)
            let fraction: Double = uncovered / length
            let fit: Double = 1 - min(1, abs(length - target) / target)
            let penalty: Double = history.penalty(start: start, bearing: bearing,
                                                  meters: target, config: config)
            let shortfall: Double = max(0, minimumNew - fraction)
            let noise: Double = Double.random(in: -1...1, using: &generator)
            let rough: Double = fraction + 0.3 * fit - penalty - 3 * shortfall
                + config.noise * noise
            candidates.append((waypoints, rough))
        }

        let budget = max(1, config.maxLegsPerPlan / steps)
        // Route more candidates than the settings ask for, so the final ranking has a real choice
        // and can reject a shape that doubles back on itself. Three is the floor when only one
        // route is asked for: one candidate leaves no alternative to prefer.
        let wanted = max(1, min(candidates.count, budget, max(routeCount * 2, 3)))
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
                        max(1, Config.destinationSteps(for: max(shape, minimumNew))))

        guard let directLegs = try? await client.route(from: start, to: destination),
              let direct = directLegs.first else { return nil }

        var routed: [PlannedRoute] = []
        if let made = makeRoute(id: 0, legs: [direct], coverage: coverage) { routed.append(made) }

        // A detour only makes sense when the user wants to walk farther than the direct way.
        if target > direct.distance * 1.05 {
            var generator = SplitMix64(seed: seed &+ 1)
            // Four detours rather than two: the zigzag is what makes a route walk the same
            // street twice, and the final ranking needs a real alternative to reject it with.
            // The budget leaves room for four at five steps — one direct leg, four detours of
            // five, and one correction of five — and fewer when the shape asks for more.
            let detourCount = min(4, max(2, (config.maxLegsPerPlan - 1 - steps) / steps))
            let jitters = (0..<detourCount).map { _ in
                Double.random(in: -10...10, using: &generator)
            }
            let sides: [Double] = [-1, 1, -1, 1]

            var rounds: [(side: Double, jitter: Double, legs: [DirectionsLeg])] = []
            await withTaskGroup(of: (Int, [DirectionsLeg]?).self) { group in
                for index in 0..<detourCount {
                    let side = sides[index]
                    let jitter = jitters[index]
                    group.addTask {
                        let legs = await detourRound(start: start, destination: destination,
                                                     steps: steps, side: side, jitter: jitter,
                                                     target: target, offset: nil,
                                                     coverage: coverage, client: client)
                        return (index, legs)
                    }
                }
                var results: [(Int, [DirectionsLeg]?)] = []
                for await result in group { results.append(result) }
                results.sort { $0.0 < $1.0 }
                for (index, legs) in results {
                    if let legs {
                        rounds.append((sides[index], jitters[index], legs))
                    }
                }
            }

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
        let plan = finalize(request: request, start: start, routes: routed, history: history)
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
                          history: PlanHistory) -> RoutePlan? {
        let target = max(200, request.targetMeters)
        // A double-back is measured before scoring, so a route that walks the same street twice
        // can be dropped outright when a clean alternative exists. A dead end is the only time
        // a double-back is unavoidable, so the clean pool is only empty when there is nothing
        // else to offer.
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
        let clean = candidates.filter { $0.backtrack <= 0.05 }
        let pool = clean.isEmpty ? candidates : clean

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
            let score = 0.5 * route.newFraction + 0.3 * fit - penalty
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
