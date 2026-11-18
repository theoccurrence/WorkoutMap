import Foundation
import HealthKit
import CoreLocation

struct Workout: Identifiable {
    let id: UUID
    let hk: HKWorkout
    let category: WorkoutCategory
    let start: Date
    let duration: TimeInterval
    let distance: Double
    let elevationAscended: Double?
    let activeCalories: Double?
    let avgHeartRate: Double?
    let temperature: Double?
    let humidity: Double?
    let sourceName: String

    init?(hk: HKWorkout) {
        guard let category = WorkoutCategory.from(hk.workoutActivityType) else { return nil }
        self.id = hk.uuid
        self.hk = hk
        self.category = category
        self.start = hk.startDate
        self.duration = hk.duration

        let meters = hk.totalDistance?.doubleValue(for: .meter())
            ?? hk.statistics(for: .init(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            ?? hk.statistics(for: .init(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
        self.distance = meters ?? 0

        let elevation = hk.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity
        self.elevationAscended = elevation?.doubleValue(for: .meter())

        self.activeCalories = hk.statistics(for: .init(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        self.avgHeartRate = hk.statistics(for: .init(.heartRate))?
            .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        let temp = hk.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity
        self.temperature = temp?.doubleValue(for: .degreeCelsius())
        let hum = hk.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity
        self.humidity = hum?.doubleValue(for: .percent())
        self.sourceName = hk.sourceRevision.source.name
    }

#if DEBUG
    init(sampleID: UUID,
         hk: HKWorkout,
         category: WorkoutCategory,
         start: Date,
         duration: TimeInterval,
         distance: Double,
         elevationAscended: Double?,
         activeCalories: Double?,
         avgHeartRate: Double?,
         temperature: Double?,
         humidity: Double?,
         sourceName: String) {
        self.id = sampleID
        self.hk = hk
        self.category = category
        self.start = start
        self.duration = duration
        self.distance = distance
        self.elevationAscended = elevationAscended
        self.activeCalories = activeCalories
        self.avgHeartRate = avgHeartRate
        self.temperature = temperature
        self.humidity = humidity
        self.sourceName = sourceName
    }
#endif

    var distanceText: String { Fmt.distance(distance) }
    var title: String { "\(category.title) \(distanceText)" }
    var listDateText: String { Fmt.monthDay.string(from: start) }
    var detailDateText: String { Fmt.detailDate.string(from: start) }
}

extension Workout: Equatable, Hashable {
    static func == (lhs: Workout, rhs: Workout) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
