#if DEBUG
import Foundation
import HealthKit
import CoreLocation

/// Debug-only sample data so the UI can be exercised in the simulator
/// (enabled with the WM_SAMPLE_DATA=1 launch environment variable).
enum SampleData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["WM_SAMPLE_DATA"] == "1" }

    struct Spec {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let meters: Double
        let seconds: Double
        let elevation: Double
        let kcal: Double
        let heartRate: Double
        let temperature: Double?
        let humidity: Double?
        let center: CLLocationCoordinate2D
        let latSpan: Double
        let lonSpan: Double
        let shape: Int
        let centerName: String
    }

    static let specs: [Spec] = [
        Spec(year: 2026, month: 11, day: 15, hour: 11, minute: 20, meters: 2570, seconds: 10478,
             elevation: 17, kcal: 591.43, heartRate: 108, temperature: 9.4, humidity: 78,
             center: CLLocationCoordinate2D(latitude: 48.1085, longitude: 11.4785),
             latSpan: 0.0135, lonSpan: 0.0210, shape: 0, centerName: "Fuerstenried"),
        Spec(year: 2026, month: 11, day: 11, hour: 17, minute: 5, meters: 3040, seconds: 5120,
             elevation: 12, kcal: 402.10, heartRate: 104, temperature: 8.9, humidity: 81,
             center: CLLocationCoordinate2D(latitude: 48.1180, longitude: 11.5320),
             latSpan: 0.0075, lonSpan: 0.0180, shape: 1, centerName: "Sendling"),
        Spec(year: 2026, month: 11, day: 10, hour: 17, minute: 34, meters: 11120, seconds: 13215,
             elevation: 148, kcal: 1030.0, heartRate: 121, temperature: 8.3, humidity: 91,
             center: CLLocationCoordinate2D(latitude: 48.1285, longitude: 11.5345),
             latSpan: 0.0300, lonSpan: 0.0420, shape: 2, centerName: "Sendling-Westpark"),
        Spec(year: 2026, month: 11, day: 9, hour: 16, minute: 40, meters: 2460, seconds: 4680,
             elevation: 9, kcal: 318.40, heartRate: 99, temperature: 7.8, humidity: 74,
             center: CLLocationCoordinate2D(latitude: 48.1360, longitude: 11.5390),
             latSpan: 0.0110, lonSpan: 0.0040, shape: 3, centerName: "Schwanthalerhoehe"),
        Spec(year: 2026, month: 11, day: 8, hour: 10, minute: 12, meters: 2600, seconds: 5210,
             elevation: 11, kcal: 356.20, heartRate: 101, temperature: 6.4, humidity: 88,
             center: CLLocationCoordinate2D(latitude: 48.1290, longitude: 11.5010),
             latSpan: 0.0060, lonSpan: 0.0140, shape: 4, centerName: "Westend"),
        Spec(year: 2026, month: 11, day: 7, hour: 15, minute: 4, meters: 701, seconds: 1490,
             elevation: 4, kcal: 88.30, heartRate: 92, temperature: 12.1, humidity: 66,
             center: CLLocationCoordinate2D(latitude: 48.1215, longitude: 11.4690),
             latSpan: 0.0080, lonSpan: 0.0035, shape: 5, centerName: "Fuerstenried"),
        Spec(year: 2026, month: 11, day: 1, hour: 14, minute: 30, meters: 1340, seconds: 2400,
             elevation: 6, kcal: 140.60, heartRate: 88, temperature: 14.3, humidity: 59,
             center: CLLocationCoordinate2D(latitude: 48.1120, longitude: 11.4870),
             latSpan: 0.0040, lonSpan: 0.0090, shape: 6, centerName: "Fuerstenried"),
        Spec(year: 2026, month: 9, day: 14, hour: 9, minute: 15, meters: 6400, seconds: 4980,
             elevation: 240, kcal: 720.00, heartRate: 118, temperature: 27.4, humidity: 52,
             center: CLLocationCoordinate2D(latitude: 39.2130, longitude: 9.1150),
             latSpan: 0.0100, lonSpan: 0.0140, shape: 2, centerName: "Cagliari"),
        Spec(year: 2026, month: 6, day: 21, hour: 8, minute: 45, meters: 5200, seconds: 4100,
             elevation: 190, kcal: 610.00, heartRate: 116, temperature: 29.1, humidity: 48,
             center: CLLocationCoordinate2D(latitude: 39.2085, longitude: 9.1225),
             latSpan: 0.0090, lonSpan: 0.0120, shape: 0, centerName: "Cagliari"),
        Spec(year: 2026, month: 3, day: 3, hour: 18, minute: 2, meters: 3300, seconds: 3900,
             elevation: 14, kcal: 402.00, heartRate: 106, temperature: 5.2, humidity: 72,
             center: CLLocationCoordinate2D(latitude: 48.1180, longitude: 11.5520),
             latSpan: 0.0060, lonSpan: 0.0160, shape: 1, centerName: "Sendling"),
    ]

    static func track(for spec: Spec) -> [CLLocationCoordinate2D] {
        var rng = SystemRandomNumberGenerator()
        let count = spec.shape == 5 ? 80 : 240
        var points: [CLLocationCoordinate2D] = []
        var seed = UInt64(abs(spec.center.latitude * 1_000_000) + abs(spec.center.longitude * 1_000_000))
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 100000) / 100000.0
        }
        let halfLat = spec.latSpan / 2
        let halfLon = spec.lonSpan / 2
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            var lat: Double
            var lon: Double
            switch spec.shape {
            case 0:
                let angle = t * 2 * Double.pi
                lat = sin(angle) * halfLat + (t > 0.98 ? halfLat * 0.6 : 0)
                lon = cos(angle) * halfLon * (0.85 + 0.15 * sin(angle * 3))
            case 1:
                lat = (t - 0.5) * spec.latSpan * 0.6
                lat += sin(t * 6) * halfLat * 0.3
                lon = -halfLon + t * spec.lonSpan
            case 2:
                let angle = t * 2 * Double.pi
                lat = sin(angle * 2) * halfLat * (0.6 + 0.4 * cos(angle))
                lon = cos(angle * 3) * halfLon * 0.9
            case 3:
                lat = -halfLat + t * spec.latSpan
                lon = sin(t * 4) * halfLon
            case 4:
                let step = t * 6
                lat = sin(step * 2.1) * halfLat
                lon = -halfLon + t * spec.lonSpan
            case 5:
                lat = -halfLat + t * spec.latSpan
                lon = sin(t * 3) * halfLon * 0.6

            default:
                lat = sin(t * 5) * halfLat * 0.7
                lon = -halfLon + t * spec.lonSpan
            }
            _ = rng.next()
            lat += (next() - 0.5) * halfLat * 0.02
            lon += (next() - 0.5) * halfLon * 0.02
            points.append(CLLocationCoordinate2D(latitude: spec.center.latitude + lat,
                                                 longitude: spec.center.longitude + lon))
        }
        return points
    }

    /// The sample route, with one errant fix spliced in when `WM_SAMPLE_JUMPS=1` asks for it.
    ///
    /// The errant fix goes through the same detection the app puts a real route through
    /// (`WorkoutRoute.jumps(in:)`): the fixes carry the one-second spacing Health gives them, so
    /// the spliced jump is found the way a real one is. It shows as the spike a real jump makes —
    /// out to somewhere the user never was, and back.
    static func route(for spec: Spec) -> WorkoutRoute {
        let coordinates = track(for: spec)
        guard DebugLaunch.sampleJumps, coordinates.count > 4 else {
            return WorkoutRoute(coordinates: coordinates)
        }
        let start = date(spec)
        let errant = coordinates.count / 2
        let locations = coordinates.enumerated().map { index, coordinate in
            CLLocation(coordinate: index == errant ? Geo.offset(coordinate, east: 900, north: 700) : coordinate,
                       altitude: 0,
                       horizontalAccuracy: 5,
                       verticalAccuracy: 5,
                       course: -1,
                       speed: -1,
                       timestamp: start.addingTimeInterval(Double(index)))
        }
        return WorkoutRoute(locations: locations)
    }

    static let calendar = AppCalendar.calendar

    static func date(_ spec: Spec) -> Date {
        var comps = DateComponents()
        comps.year = spec.year
        comps.month = spec.month
        comps.day = spec.day
        comps.hour = spec.hour
        comps.minute = spec.minute
        return calendar.date(from: comps) ?? Date()
    }

    @MainActor
    static func makeWorkouts() -> [Workout] {
        var made: [Workout] = []
        // WM_STRESS replicates the samples (spread out) so the map can be
        // exercised with a realistic number of routes.
        for copy in 0..<DebugLaunch.stressCopies {
            let offset = Double(copy) * DebugLaunch.stressSpread
            for (index, spec) in specs.enumerated() {
                let shifted = Spec(year: spec.year, month: spec.month, day: spec.day,
                                   hour: spec.hour, minute: spec.minute,
                                   meters: spec.meters, seconds: spec.seconds,
                                   elevation: spec.elevation, kcal: spec.kcal,
                                   heartRate: spec.heartRate,
                                   temperature: spec.temperature, humidity: spec.humidity,
                                   center: CLLocationCoordinate2D(latitude: spec.center.latitude + offset,
                                                                  longitude: spec.center.longitude + offset),
                                   latSpan: spec.latSpan, lonSpan: spec.lonSpan,
                                   shape: spec.shape, centerName: spec.centerName)
                let start = date(spec)
                let hk = HKWorkout(activityType: .walking,
                                   start: start,
                                   end: start.addingTimeInterval(spec.seconds),
                                   duration: spec.seconds,
                                   totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: spec.kcal),
                                   totalDistance: HKQuantity(unit: .meter(), doubleValue: spec.meters),
                                   metadata: nil)
                let workout = Workout(sampleID: UUID(uuidString: String(format: "%08X-0000-0000-0000-%012X", copy + 1, index + 1))!,
                                      hk: hk,
                                      category: .walk,
                                      start: start,
                                      duration: spec.seconds,
                                      distance: spec.meters,
                                      elevationAscended: spec.elevation,
                                      activeCalories: spec.kcal,
                                      avgHeartRate: spec.heartRate,
                                      temperature: spec.temperature,
                                      humidity: spec.humidity,
                                      sourceName: "Sandro\u{2019}s Apple Watch")
                routes[workout.id] = route(for: shifted)
                made.append(workout)
            }
        }
        return made
    }

    static var routes: [UUID: WorkoutRoute] = [:]
}
#endif
