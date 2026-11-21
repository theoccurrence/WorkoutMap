import Foundation
import HealthKit
import CoreLocation
import MapKit

/// Loads workout routes from HealthKit, keeps them in memory and mirrors them on disk
/// so the map and the list thumbnails do not re-query Health on every launch.
///
/// `@unchecked Sendable`: the disk read runs off the main thread (`cachedRoutes`),
/// and everything mutable is behind `lock`.
final class RouteStore: @unchecked Sendable {
    static let shared = RouteStore()

    private let store = HKHealthStore()
    private var memory: [UUID: WorkoutRoute] = [:]
    private var inFlight: [UUID: Task<WorkoutRoute, Never>] = [:]
    private let lock = NSLock()

    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func fileURL(_ id: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(id.uuidString).bin")
    }

    func cached(_ id: UUID) -> WorkoutRoute? {
#if DEBUG
        if SampleData.isEnabled, let sample = SampleData.routes[id] { return sample }
#endif
        lock.lock()
        if let m = memory[id] { lock.unlock(); return m }
        lock.unlock()
        guard let data = try? Data(contentsOf: fileURL(id)),
              let route = RouteStore.decode(data) else { return nil }
        lock.lock(); memory[id] = route; lock.unlock()
        return route
    }

    /// Everything the cache holds for a whole filter's worth of workouts, read off
    /// the main thread: a year or "all" range asks for hundreds of files at once.
    func cachedRoutes(for ids: [UUID]) async -> [UUID: WorkoutRoute] {
#if DEBUG
        if SampleData.isEnabled { return cachedMap(for: ids) }
#endif
        return await Task.detached(priority: .userInitiated) { [self] in cachedMap(for: ids) }.value
    }

    private func cachedMap(for ids: [UUID]) -> [UUID: WorkoutRoute] {
        var found: [UUID: WorkoutRoute] = [:]
        found.reserveCapacity(ids.count)
        for id in ids {
            if let coords = cached(id) { found[id] = coords }
        }
        return found
    }

    func route(for workout: HKWorkout) async -> WorkoutRoute {
        if let cached = cached(workout.uuid) { return cached }

        lock.lock()
        if let task = inFlight[workout.uuid] {
            lock.unlock()
            return await task.value
        }
        let task = Task<WorkoutRoute, Never> { [weak self] in
            guard let self else { return WorkoutRoute(coordinates: []) }
            let route = await self.queryRoute(for: workout)
            if !route.isEmpty {
                self.store(route, for: workout.uuid)
            }
            return route
        }
        inFlight[workout.uuid] = task
        lock.unlock()

        let value = await task.value
        lock.lock(); inFlight[workout.uuid] = nil; lock.unlock()
        return value
    }

    private func store(_ route: WorkoutRoute, for id: UUID) {
        lock.lock(); memory[id] = route; lock.unlock()
        try? RouteStore.encode(route).write(to: fileURL(id), options: .atomic)
    }

    private func queryRoute(for workout: HKWorkout) async -> WorkoutRoute {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        guard !routes.isEmpty else { return WorkoutRoute(coordinates: []) }

        var locations: [CLLocation] = []
        for route in routes {
            let part: [CLLocation] = await withCheckedContinuation { continuation in
                var collected: [CLLocation] = []
                var finished = false
                let query = HKWorkoutRouteQuery(route: route) { _, fixes, done, error in
                    guard !finished else { return }
                    if let fixes { collected.append(contentsOf: fixes) }
                    if error != nil || done {
                        finished = true
                        continuation.resume(returning: collected)
                    }
                }
                store.execute(query)
            }
            locations.append(contentsOf: part)
        }
        return WorkoutRoute(locations: locations)
    }

    /// The cache's own format: `WMR1`, then the fix count, the coordinates, and one byte per fix
    /// saying whether the leg that arrives at it is a jump.
    ///
    /// The count and the coordinates alone are what this file held before the jumps were told
    /// apart, and a file in that shape cannot say where they are, so it is refused rather than
    /// read as a route without any — the workout is fetched from Health again, which is where
    /// the jumps come from.
    private static let magic = Array("WMR1".utf8)
    /// Four bytes of magic and four of count, before the coordinates.
    private static let header = 8
    /// One coordinate, and one byte of jump flag per fix.
    private static let stride = 17

    static func encode(_ route: WorkoutRoute) -> Data {
        var data = Data(capacity: header + route.coordinates.count * stride)
        data.append(contentsOf: magic)
        var count = UInt32(route.coordinates.count).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for c in route.coordinates {
            var lat = c.latitude.bitPattern.littleEndian
            var lon = c.longitude.bitPattern.littleEndian
            withUnsafeBytes(of: &lat) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &lon) { data.append(contentsOf: $0) }
        }
        for index in route.coordinates.indices {
            data.append(route.jumps.contains(index) ? 1 : 0)
        }
        return data
    }

    static func decode(_ data: Data) -> WorkoutRoute? {
        guard data.count >= header, Array(data.prefix(magic.count)) == magic else { return nil }
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian)
        guard data.count >= header + count * stride else { return nil }
        let flagOffset = header + count * 16
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(count)
        var jumps: Set<Int> = []
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let lat = raw.loadUnaligned(fromByteOffset: header + i * 16, as: UInt64.self).littleEndian
                let lon = raw.loadUnaligned(fromByteOffset: header + i * 16 + 8, as: UInt64.self).littleEndian
                coords.append(CLLocationCoordinate2D(latitude: Double(bitPattern: lat),
                                                     longitude: Double(bitPattern: lon)))
                if raw.loadUnaligned(fromByteOffset: flagOffset + i, as: UInt8.self) != 0 {
                    jumps.insert(i)
                }
            }
        }
        return WorkoutRoute(coordinates: coords, jumps: jumps)
    }
}
