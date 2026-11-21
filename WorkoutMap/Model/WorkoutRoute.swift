import Foundation
import CoreLocation

/// One workout’s GPS track, with the legs the receiver jumped told apart from the legs the
/// user actually walked.
///
/// Health hands a workout route over as the fixes the receiver took, roughly one per second.
/// When it loses its fix the position reported next can be somewhere it never was — hundreds
/// of metres away within the time one fix takes — and the polyline joins the two points with a
/// straight line across whatever lies between them: houses, gardens, a lake. The Fitness app
/// does not draw such a leg as ground the user covered; it draws it as a dashed grey line
/// (see `RouteJumpStyle`). This type carries which legs those are.
struct WorkoutRoute {
    /// The fixes, in the order the receiver took them.
    var coordinates: [CLLocationCoordinate2D]
    /// The legs that are jumps: `i` means the leg from `coordinates[i - 1]` to
    /// `coordinates[i]` is one.
    var jumps: Set<Int>

    init(coordinates: [CLLocationCoordinate2D], jumps: Set<Int> = []) {
        self.coordinates = coordinates
        self.jumps = jumps
    }

    /// The track as Health has it, with the jumps found in it.
    init(locations: [CLLocation]) {
        self.coordinates = locations.map(\.coordinate)
        self.jumps = WorkoutRoute.jumps(in: locations)
    }

    var isEmpty: Bool { coordinates.isEmpty }
    var count: Int { coordinates.count }

    // MARK: detecting the jumps

    /// How fast a leg would have to be to still be the user moving: a jump beats 162 km/h,
    /// which is past any human and past a car on a country road, and covers at least 25 m, so a
    /// duplicate fix a metre away in a hundredth of a second — a badly rounded timestamp, not a
    /// jump — is let through. The plain-distance limit is what is left when a sample carries no
    /// usable timestamp at all: no fix interval can cover that much ground at any speed.
    static let implausibleSpeed: Double = 45          // m/s ≈ 162 km/h
    static let jumpMinimumDistance: Double = 25       // m
    static let jumpDistanceWithoutTime: Double = 300  // m

    /// The legs of a track that the receiver made up, i.e. the ones that cannot have been
    /// travelled: they cover real ground and the applied speed is impossible.
    ///
    /// This is the only way to tell a jump from ground the user covered. Health stores a jump
    /// as an ordinary fix, and the straight line across the map is exactly what a polyline
    /// draws between any two fixes — the impossibility is in the time between them, which only
    /// the fixes themselves carry.
    static func jumps(in locations: [CLLocation]) -> Set<Int> {
        guard locations.count > 1 else { return [] }
        var jumps: Set<Int> = []
        for index in 1..<locations.count {
            let previous = locations[index - 1]
            let current = locations[index]
            let distance = current.distance(from: previous)
            guard distance > jumpMinimumDistance else { continue }
            let seconds = current.timestamp.timeIntervalSince(previous.timestamp)
            if seconds > 0 {
                if distance / seconds > implausibleSpeed { jumps.insert(index) }
            } else if distance > jumpDistanceWithoutTime {
                jumps.insert(index)
            }
        }
        return jumps
    }

    // MARK: drawing

    /// How a track is split up for drawing.
    struct Drawing {
        /// The stretches the user walked, separated where a jump interrupts them.
        let walked: [[CLLocationCoordinate2D]]
        /// Each jump as the two fixes it spans.
        let jumps: [[CLLocationCoordinate2D]]
    }

    /// Splits the track the way `style` says it should be drawn. `solid` hands the whole track
    /// back as one run — what this app drew before the jumps were told apart — and `hidden`
    /// keeps the separation without the grey line, so a jump is simply not there.
    func drawing(_ style: RouteJumpStyle) -> Drawing {
        guard !jumps.isEmpty, style != .solid else {
            return Drawing(walked: [coordinates], jumps: [])
        }
        var walked: [[CLLocationCoordinate2D]] = []
        var run: [CLLocationCoordinate2D] = []
        for index in coordinates.indices {
            // `index > 0`: the first fix has no leg arriving at it and is never a jump.
            if index > 0, jumps.contains(index) {
                if run.count > 1 { walked.append(run) }
                run = [coordinates[index]]
            } else {
                run.append(coordinates[index])
            }
        }
        if run.count > 1 { walked.append(run) }

        var drawn: [[CLLocationCoordinate2D]] = []
        if style == .dotted {
            // Sorted, so the lines keep the order they run in on the map.
            for index in jumps.sorted() where index > 0 && index < coordinates.count {
                drawn.append([coordinates[index - 1], coordinates[index]])
            }
        }
        return Drawing(walked: walked, jumps: drawn)
    }
}
