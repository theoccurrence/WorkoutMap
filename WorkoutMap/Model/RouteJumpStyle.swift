import Foundation

/// What the map does with a GPS jump — a leg of a route the receiver made up while it had no
/// fix, joining two fixes with a straight line across whatever lies between them
/// (`WorkoutRoute.jumps`).
///
/// `dotted` is what the Fitness app draws: a dashed grey line, so it is clear the user did
/// not walk that ground. `hidden` leaves the jump out altogether and shows only what the
/// workout data measured. `solid` is what this app drew before the jumps were told apart.
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

    /// Where the settings keep it.
    static let storedKey = "routeJumpStyle"

    /// What the map opens with: the dashed grey line the Fitness app draws, so a jump never
    /// reads as ground the user covered.
    static var stored: RouteJumpStyle {
        guard let raw = UserDefaults.standard.string(forKey: storedKey) else { return .dotted }
        return RouteJumpStyle(rawValue: raw) ?? .dotted
    }
}
