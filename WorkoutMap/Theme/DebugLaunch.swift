import Foundation
import CoreLocation

/// Debug-only launch hooks so screens can be opened directly from the simulator
/// command line (WM_START_TAB, WM_START_RANGE, WM_START_CATEGORY, ...).
enum DebugLaunch {
#if DEBUG
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var startTab: Int { Int(env["WM_START_TAB"] ?? "0") ?? 0 }
    static var openDetail: Bool { env["WM_START_DETAIL"] == "1" }
    static var openExport: Bool { env["WM_START_EXPORT"] == "1" }
    static var openSheet: Bool { env["WM_START_SHEET"] == "1" }
    static var startCategory: WorkoutCategory? { env["WM_START_CATEGORY"].flatMap(WorkoutCategory.init(rawValue:)) }
    /// WM_SKIP_LOCATION=1 skips the location prompt (simulator screenshots).
    static var skipLocation: Bool { env["WM_SKIP_LOCATION"] == "1" }
    /// WM_STRESS=N replicates the sample workouts N times (performance testing).
    static var stressCopies: Int { max(1, Int(env["WM_STRESS"] ?? "1") ?? 1) }
    /// WM_STRESS_SPREAD=degrees between replicated clusters (default 0.035).
    static var stressSpread: Double { Double(env["WM_STRESS_SPREAD"] ?? "") ?? 0.035 }
    /// WM_FAKE_LOCATION="lat,lon" publishes a fixed position (checks the dot).
    static var fakeLocation: CLLocationCoordinate2D? {
        guard let raw = env["WM_FAKE_LOCATION"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    static var startSelection: RangeSelection? {
        switch env["WM_START_RANGE"] {
        case "week": return .week(0)
        case "month": return .month(11, 2026)
        case "year": return .year(2026)
        case "all": return .all
        default: return nil
        }
    }
#else
    static var startTab: Int { 0 }
    static var openDetail: Bool { false }
    static var openExport: Bool { false }
    static var openSheet: Bool { false }
    static var startCategory: WorkoutCategory? { nil }
    static var skipLocation: Bool { false }
    static var stressCopies: Int { 1 }
    static var stressSpread: Double { 0.035 }
    static var fakeLocation: CLLocationCoordinate2D? { nil }
    static var startSelection: RangeSelection? { nil }
#endif
}
