import Foundation

/// The two things the settings let the user steer about the explorer. The values themselves are
/// read through `@AppStorage` by the screens that use them — the map screen hands them to the
/// planner — so this is only where the keys, the defaults and the labels live.
enum ExploreOptions {
    /// How many routes are offered at once.
    static let routeCountKey = "exploreRouteCount"
    static let routeCountDefault = 3
    /// One is "just give me a route"; five is as many as the request budget sensibly pays for,
    /// since every route is three to five `MKDirections` legs of its own.
    static let routeCounts = [1, 2, 3, 4, 5]

    /// How tight the route stays, 0...1.
    ///
    /// At 0 the planner makes the widest shape it can: for a loop two long legs out and back
    /// around the start, for a destination one big bow off the direct line. At 1 it fills the
    /// streets around the route instead — a lawnmower over the square the start sits in, or a
    /// zigzag of side streets either side of the way to the destination — reaching the distance
    /// asked for by taking more, smaller steps rather than by going further out.
    static let shapeKey = "exploreShape"
    static let shapeDefault = 0.5

    /// How much of the route the planner should try to keep on ground the user has never
    /// covered, 0.1...1.
    ///
    /// It is a target rather than a guarantee: a route that starts at the front door has to
    /// cross the streets around it, and those are the streets most likely to be covered already.
    /// What the planner does with it is hunt — it tries the shape over a ring of centres around
    /// the start instead of only at the start, nudges every turning point towards the least
    /// covered ground nearby, keeps the shape as tight as the setting asks for, and then ranks
    /// what came back by how close it got. A park whose little paths were never walked is
    /// exactly the ground this finds.
    static let minimumNewKey = "exploreMinimumNew"
    static let minimumNewDefault = 0.5
    static let minimumNewRange: ClosedRange<Double> = 0.1...1.0

    static func percentLabel(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func shapeLabel(_ shape: Double) -> String {
        switch shape {
        case ..<0.2: return "Wide"
        case ..<0.4: return "Wide-ish"
        case ..<0.6: return "Balanced"
        case ..<0.8: return "Tight-ish"
        default: return "Tight"
        }
    }
}
