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
    private var memory: [UUID: [CLLocationCoordinate2D]] = [:]
    private var inFlight: [UUID: Task<[CLLocationCoordinate2D], Never>] = [:]
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

    func cached(_ id: UUID) -> [CLLocationCoordinate2D]? {
#if DEBUG
        if SampleData.isEnabled, let sample = SampleData.routes[id] { return sample }
#endif
        lock.lock()
        if let m = memory[id] { lock.unlock(); return m }
        lock.unlock()
        guard let data = try? Data(contentsOf: fileURL(id)), data.count >= 16 else { return nil }
        let coords = RouteStore.decode(data)
        lock.lock(); memory[id] = coords; lock.unlock()
        return coords
    }

    /// Everything the cache holds for a whole filter's worth of workouts, read off
    /// the main thread: a year or "all" range asks for hundreds of files at once.
    func cachedRoutes(for ids: [UUID]) async -> [UUID: [CLLocationCoordinate2D]] {
#if DEBUG
        if SampleData.isEnabled { return cachedMap(for: ids) }
#endif
        return await Task.detached(priority: .userInitiated) { [self] in cachedMap(for: ids) }.value
    }

    private func cachedMap(for ids: [UUID]) -> [UUID: [CLLocationCoordinate2D]] {
        var found: [UUID: [CLLocationCoordinate2D]] = [:]
        found.reserveCapacity(ids.count)
        for id in ids {
            if let coords = cached(id) { found[id] = coords }
        }
        return found
    }

    func route(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        if let cached = cached(workout.uuid) { return cached }

        lock.lock()
        if let task = inFlight[workout.uuid] {
            lock.unlock()
            return await task.value
        }
        let task = Task<[CLLocationCoordinate2D], Never> { [weak self] in
            guard let self else { return [] }
            let coords = await self.queryRoute(for: workout)
            if !coords.isEmpty {
                self.store(coords, for: workout.uuid)
            }
            return coords
        }
        inFlight[workout.uuid] = task
        lock.unlock()

        let value = await task.value
        lock.lock(); inFlight[workout.uuid] = nil; lock.unlock()
        return value
    }

    private func store(_ coords: [CLLocationCoordinate2D], for id: UUID) {
        lock.lock(); memory[id] = coords; lock.unlock()
        try? RouteStore.encode(coords).write(to: fileURL(id), options: .atomic)
    }

    private func queryRoute(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
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
        guard !routes.isEmpty else { return [] }

        var coords: [CLLocationCoordinate2D] = []
        for route in routes {
            let part: [CLLocationCoordinate2D] = await withCheckedContinuation { continuation in
                var collected: [CLLocationCoordinate2D] = []
                var finished = false
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    guard !finished else { return }
                    if let locations { collected.append(contentsOf: locations.map(\.coordinate)) }
                    if error != nil || done {
                        finished = true
                        continuation.resume(returning: collected)
                    }
                }
                store.execute(query)
            }
            coords.append(contentsOf: part)
        }
        return coords
    }

    static func encode(_ coords: [CLLocationCoordinate2D]) -> Data {
        var data = Data(capacity: coords.count * 16)
        for c in coords {
            var lat = c.latitude.bitPattern.littleEndian
            var lon = c.longitude.bitPattern.littleEndian
            withUnsafeBytes(of: &lat) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &lon) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [CLLocationCoordinate2D] {
        let count = data.count / 16
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let lat = raw.loadUnaligned(fromByteOffset: i * 16, as: UInt64.self).littleEndian
                let lon = raw.loadUnaligned(fromByteOffset: i * 16 + 8, as: UInt64.self).littleEndian
                coords.append(CLLocationCoordinate2D(latitude: Double(bitPattern: lat),
                                                     longitude: Double(bitPattern: lon)))
            }
        }
        return coords
    }
}
