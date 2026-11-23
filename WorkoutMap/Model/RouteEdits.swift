import Foundation

/// What the user has changed about how a workout's route is *drawn*, in the app's own route
/// editor: the legs the eraser took out of the line, and the legs flagged as ground they really
/// covered where a GPS-jump rule says otherwise.
///
/// Health's workouts and their routes cannot be changed — not by this app and not by the Fitness
/// app — so an edit is kept **beside** the route rather than written into it: the route stays
/// exactly as Health handed it over, and this value says which of its legs are not drawn and which
/// of them the jump rules must leave alone. A leg is named by its index in the route's own leg
/// sequence — the leg arriving at `coordinates[i]` is leg `i` — and each set is coalesced into as
/// few closed ranges as there are stretches, so an erased stretch costs two numbers and the render
/// path pays nothing per fix.
///
/// The granularity is the **leg**, not the fix, and that is what makes both halves work: a leg the
/// strict GPS-jump rule catches is a leg of its own, a leg a softer rule draws as a dotted line is
/// a leg of its own, and both erasing one and flagging one is naming one index. Two fixes that were
/// only ever joined by an erased leg are never joined again — the drawing never invents a leg — so
/// erasing a stretch of a route cannot leave a phantom line across the gap.
///
/// The two sets never overlap: erasing a leg takes it out of `validated` and flagging it takes it
/// out of `erased`, because the two say opposite things about the same ground.
struct RouteEdits: Equatable {
    /// The erased legs: ground the line leaves out entirely.
    private(set) var erased: IndexSet
    /// The validated legs: ground a jump rule would flag, which the user says they covered. The map
    /// and the list draw such a leg as part of the route — that is the point of flagging it — while
    /// the workout's own screens still draw it as the jump it is, so the flag can be seen and
    /// changed (`MapRouteLine.lines`).
    private(set) var validated: IndexSet

    static let empty = RouteEdits()

    init(erased: IndexSet = [], validated: IndexSet = []) {
        self.erased = erased
        self.validated = validated
    }

    var isEmpty: Bool { erased.isEmpty && validated.isEmpty }

    /// This value with `more` erased — the eraser's stroke. A leg that is flagged and then erased is
    /// erased: the two say opposite things about the same ground, and the eraser is the one the user
    /// just used.
    func erasing(_ more: IndexSet) -> RouteEdits {
        guard !more.isEmpty else { return self }
        return RouteEdits(erased: erased.union(more), validated: validated.subtracting(more))
    }

    /// This value with `more` flagged as ground the user covered — the *valid* tool's stroke.
    func validating(_ more: IndexSet) -> RouteEdits {
        guard !more.isEmpty else { return self }
        return RouteEdits(erased: erased.subtracting(more), validated: validated.union(more))
    }

    /// This value plus another's edits — what an import unions into what is already here, so
    /// importing twice changes nothing and never loses an edit made on this device. A leg one side
    /// erased and the other flagged is **erased**: taking ground out of the line is the stronger of
    /// the two statements, and the drawing would have nothing to flag if it were the other way.
    func merging(_ other: RouteEdits) -> RouteEdits {
        RouteEdits(erased: erased.union(other.erased),
                   validated: validated.union(other.validated).subtracting(erased.union(other.erased)))
    }

    /// What the edit does to the route, in a few words — the line a list row shows under the
    /// workout's name, and nothing else.
    var summary: String {
        var parts: [String] = []
        if !erased.isEmpty { parts.append("erased") }
        // "flagged" is the word the rest of the app uses for a jump the user says really happened,
        // and a count is all that fits beside a workout's date.
        if !validated.isEmpty { parts.append("\(validated.count) flagged") }
        return parts.joined(separator: " · ")
    }

    /// A short, stable form for caches that have to be cut again when the edits move.
    var key: String { "\(Self.text(from: erased))|\(Self.text(from: validated))" }

    /// The forms the database and the exported file keep: `12-40,58` for a set, `""` for none.
    var storedErased: String { Self.text(from: erased) }
    var storedValidated: String { Self.text(from: validated) }

    /// Reads those forms back. `nil` for anything malformed, so a corrupt row is dropped rather than
    /// read as an edit the user never made.
    init?(storedErased: String, storedValidated: String) {
        guard let erased = Self.parse(storedErased),
              let validated = Self.parse(storedValidated) else { return nil }
        self.init(erased: erased, validated: validated)
    }

    private static func text(from legs: IndexSet) -> String {
        legs.rangeView
            .map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound - 1)" }
            .joined(separator: ",")
    }

    private static func parse(_ text: String) -> IndexSet? {
        guard !text.isEmpty else { return [] }
        var set = IndexSet()
        for part in text.split(separator: ",") {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            switch ends.count {
            case 1:
                guard ends[0] > 0 else { return nil }
                set.insert(ends[0])
            case 2:
                guard ends[0] > 0, ends[0] <= ends[1] else { return nil }
                set.insert(integersIn: ends[0]...ends[1])
            default:
                return nil
            }
        }
        return set
    }
}
