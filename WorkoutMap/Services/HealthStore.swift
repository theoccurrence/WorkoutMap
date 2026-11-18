import Foundation
import HealthKit

@MainActor
final class HealthStore: ObservableObject {
    enum Status { case unknown, unavailable, ready, failed }

    @Published private(set) var workouts: [Workout] = []
    @Published private(set) var status: Status = .unknown
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

    let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }

    func bootstrap() async {
#if DEBUG
        if SampleData.isEnabled {
            status = .ready
            workouts = SampleData.makeWorkouts()
            RangeSelection.updateBounds(from: workouts)
            didLoad = true
            return
        }
#endif
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            status = .failed
            return
        }
        status = .ready
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
            WorkoutCategory.allActivityTypes.map { HKQuery.predicateForWorkouts(with: $0) })
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, samples, _ in
            let hkWorkouts = (samples as? [HKWorkout]) ?? []
            Task { @MainActor in
                self.workouts = hkWorkouts.compactMap { Workout(hk: $0) }
                RangeSelection.updateBounds(from: self.workouts)
                self.didLoad = true
            }
        }
        store.execute(query)
    }
}
