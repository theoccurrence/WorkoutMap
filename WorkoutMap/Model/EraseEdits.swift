import Foundation

/// What the user has erased from a workout's route in the app's own edit mode.
///
/// Health's workouts and their routes cannot be changed — not by this app and not by the
/// Fitness app — so an edit is kept **beside** the route rather than written into it: the route
/// stays exactly as Health handed it over, and this value says which of its legs are not drawn.
/// A leg is named by its index in the route's own leg sequence — the leg arriving at
/// `coordinates[i]` is leg `i` — and the erased legs are coalesced into as few closed ranges as
/// there are erased stretches, so a whole erased stretch costs two numbers and the render path
/// pays nothing per fix.
///
/// The granularity is the **leg**, not the fix, and that is what makes the eraser work on the
/// jumps as well: a leg the strict GPS-jump rule catches is a leg of its own, a leg a softer rule
/// draws as a dotted line is a leg of its own, and erasing any of them is erasing one index. Two
/// fixes that were only ever joined by an erased leg are never joined again — the drawing never
/// invents a leg — so erasing a stretch of a route cannot leave a phantom line across the gap.
struct EraseEdits: Equatable {
    /// The erased legs, as a set of indices. Contiguous stretches collapse into single ranges on
    /// their own, and "is this leg drawn" is one lookup. Leg `i` is the leg arriving at
    /// `coordinates[i]`, so `0` is never in here and the largest index is one less than the fix
    /// count.
    private(set) var legs: IndexSet

    static let empty = EraseEdits()

    init(legs: IndexSet = []) {
        self.legs = legs
    }

    var isEmpty: Bool { legs.isEmpty }

    /// Whether the leg arriving at `index` has been erased.
    func contains(_ index: Int) -> Bool { legs.contains(index) }

    /// This value plus more erased legs, coalesced.
    func erasing(_ more: IndexSet) -> EraseEdits {
        guard !more.isEmpty else { return self }
        var union = legs
        union.formUnion(more)
        return EraseEdits(legs: union)
    }

    /// This value plus another's erased legs, coalesced — what an import unions into what is
    /// already here, so importing twice changes nothing and never loses an edit made on this
    /// device.
    func merging(_ other: EraseEdits) -> EraseEdits { erasing(other.legs) }

    /// A short, stable form for caches that have to be cut again when the edits move.
    var key: String { Self.text(from: legs) }

    /// The form the database keeps: `12-40,58` for the erased legs, `""` for none.
    var stored: String { Self.text(from: legs) }

    /// Reads the database's own form back. `nil` for anything malformed, so a corrupt row is
    /// dropped rather than read as an edit the user never made.
    init?(stored: String) {
        guard !stored.isEmpty else {
            self.init()
            return
        }
        var set = IndexSet()
        for part in stored.split(separator: ",") {
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
        self.init(legs: set)
    }

    private static func text(from legs: IndexSet) -> String {
        legs.rangeView
            .map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound - 1)" }
            .joined(separator: ",")
    }
}
