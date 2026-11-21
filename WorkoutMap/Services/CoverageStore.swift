import Foundation
import Combine
import CoreLocation

/// Keeps the explorer's `CoverageIndex` up to date for **every** workout, whatever range the
/// map is filtered to — "where have I never been" is not a question about the current filter.
///
/// The routes already on disk are read first, so the index is usable the moment the screen
/// opens; the rest are pulled from Health in the background, a few at a time, and folded in as
/// they arrive. `index(for:)` waits only for the first of those two.
@MainActor
final class CoverageStore: ObservableObject {
    @Published private(set) var index = CoverageIndex()
    /// True while the routes that were not on disk yet are still being read. The explorer says
    /// so, because a plan made before that finishes is scored against less than the user's
    /// whole history.
    @Published private(set) var isFilling = false

    private var signature: [UUID] = []
    private var loaded: Set<UUID> = []
    private var cachedBuild: Task<(index: CoverageIndex, ids: Set<UUID>), Never>?
    private var fillTask: Task<Void, Never>?
    private var generation = 0

    /// How many routes are pulled from Health at once while the index is being filled in.
    private static let fillConcurrency = 4
    /// How many arrivals are folded into the published index at once, so a long fill does not
    /// republish the whole screen once per route.
    private static let batch = 20

    /// Rebuilds the index for a new workout set. Cheap to call repeatedly: an unchanged set is
    /// ignored.
    func update(workouts: [Workout]) {
        let ids = workouts.map(\.id)
        guard ids != signature else { return }
        signature = ids
        generation += 1
        let gen = generation
        fillTask?.cancel()
        loaded = []
        index = CoverageIndex()

        let build = Task {
            let cached = await RouteStore.shared.cachedRoutes(for: ids)
            var built = CoverageIndex()
            for (_, route) in cached { built.insert(route.coordinates) }
            return (index: built, ids: Set(cached.keys))
        }
        cachedBuild = build
        fillTask = Task {
            let cached = await build.value
            guard gen == generation else { return }
            index = cached.index
            loaded = cached.ids
            await fill(workouts: workouts, generation: gen)
        }
    }

    /// The index as far as it is known, once the routes already on disk have been read. The
    /// background fill keeps going afterwards and folds the rest in.
    func index(for workouts: [Workout]) async -> CoverageIndex {
        update(workouts: workouts)
        guard let built = await cachedBuild?.value else { return index }
        if index.isEmpty { index = built.index }
        return index
    }

    private func fill(workouts: [Workout], generation gen: Int) async {
        let missing = workouts.filter { !loaded.contains($0.id) }
        guard !missing.isEmpty else { return }
        isFilling = true
        defer { isFilling = false }

        await withTaskGroup(of: (UUID, [CLLocationCoordinate2D]).self) { group in
            var iterator = missing.makeIterator()
            func addNext() {
                guard let workout = iterator.next() else { return }
                group.addTask { (workout.id, await RouteStore.shared.route(for: workout.hk).coordinates) }
            }
            for _ in 0..<Self.fillConcurrency { addNext() }

            var pending: [(UUID, [CLLocationCoordinate2D])] = []
            for await arrival in group {
                if gen != generation { group.cancelAll(); return }
                pending.append(arrival)
                if pending.count >= Self.batch { fold(&pending) }
                addNext()
            }
            fold(&pending)
        }
    }

    /// Folds a batch of arrivals into the published index in one assignment.
    private func fold(_ pending: inout [(UUID, [CLLocationCoordinate2D])]) {
        guard !pending.isEmpty else { return }
        var built = index
        for (id, coordinates) in pending {
            loaded.insert(id)
            built.insert(coordinates)
        }
        pending.removeAll(keepingCapacity: true)
        index = built
    }
}
