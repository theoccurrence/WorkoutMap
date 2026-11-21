import Foundation

/// How one of the two softer jump rules is drawn — a leg of a route the receiver made up while
/// it had no fix, or a leg it reported at an impossible speed (`WorkoutRoute.drawing`).
///
/// `dotted` is what the Fitness app draws: a dotted line, so it is clear the user did not walk
/// that ground. `hidden` leaves the leg out altogether and shows only what the workout data
/// measured — the gap in the line is the point. `solid` draws the leg as a line of its own, in
/// the rule's own tone rather than the route's colour, so it reads as a note about the leg and
/// not as ground the user covered.
enum RouteJumpStyle: String, CaseIterable, Identifiable {
    case dotted, hidden, solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dotted: return "Dotted"
        case .hidden: return "Hidden"
        case .solid: return "Solid"
        }
    }
}
