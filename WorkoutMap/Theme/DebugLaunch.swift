import Foundation
import CoreLocation
import UIKit

/// Debug-only launch hooks so screens can be opened directly from the simulator
/// command line (WM_START_TAB, WM_START_RANGE, WM_START_CATEGORY, ...).
enum DebugLaunch {
#if DEBUG
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var startTab: Int { Int(env["WM_START_TAB"] ?? "0") ?? 0 }
    static var openDetail: Bool { env["WM_START_DETAIL"] == "1" }
    static var openExport: Bool { env["WM_START_EXPORT"] == "1" }
    /// WM_START_SHEET=1 opens the calendar picker (the flag keeps the name it shipped with).
    static var openSheet: Bool { env["WM_START_SHEET"] == "1" }
    static var startCategory: WorkoutCategory? { env["WM_START_CATEGORY"].flatMap(WorkoutCategory.init(rawValue:)) }
    /// WM_START_MODE=explore|driving|transit|satellite|legacy picks the map style.
    static var startMapMode: MapMode? { env["WM_START_MODE"].flatMap(MapMode.init(rawValue:)) }
    /// WM_START_APPEARANCE=system|light|dark picks how the map is drawn.
    static var startAppearance: MapAppearance? { env["WM_START_APPEARANCE"].flatMap(MapAppearance.init(rawValue:)) }
    /// WM_START_JUMP_STYLE=dotted|hidden|solid picks what the map does with a GPS jump.
    static var startJumpStyle: RouteJumpStyle? { env["WM_START_JUMP_STYLE"].flatMap(RouteJumpStyle.init(rawValue:)) }
    /// WM_SAMPLE_JUMPS=1 splices one errant fix into the sample routes, so the jump setting can
    /// be exercised without a workout whose receiver actually jumped.
    static var sampleJumps: Bool { env["WM_SAMPLE_JUMPS"] == "1" }
    /// WM_START_MODES=1 opens the map style picker.
    static var openModes: Bool { env["WM_START_MODES"] == "1" }
    /// WM_TAP_AT="x,y" fires one tap on the map at those screen points, once the routes are on
    /// screen. The simulator offers no way to send a touch from the command line and there is no
    /// Simulator UI to click, so the route tap is driven from inside — through the very path the
    /// recognizer uses (`RouteMapView.Coordinator.reportRouteTap(at:)`).
    static var tapAt: CGPoint? {
        guard let raw = env["WM_TAP_AT"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }
    /// WM_TAP_DELAY=<seconds> moves the `WM_TAP_AT` tap back, so it can land after a plan has
    /// arrived rather than before it.
    static var tapDelay: Double { Double(env["WM_TAP_DELAY"] ?? "") ?? 4 }
    /// WM_HIDE_CARD=1 parks the explorer's result card a few seconds after it appears and brings
    /// it back a few seconds later, so both states can be seen without a drag.
    static var hideCard: Bool { env["WM_HIDE_CARD"] == "1" }
    /// WM_SKIP_LOCATION=1 skips the location prompt (simulator screenshots).
    static var skipLocation: Bool { env["WM_SKIP_LOCATION"] == "1" }
    /// WM_STRESS=N replicates the sample workouts N times (performance testing).
    static var stressCopies: Int { max(1, Int(env["WM_STRESS"] ?? "1") ?? 1) }
    /// WM_STRESS_SPREAD=degrees between replicated clusters (default 0.035).
    static var stressSpread: Double { Double(env["WM_STRESS_SPREAD"] ?? "") ?? 0.035 }
    /// WM_FAKE_HEADING=<degrees|cycle> publishes a compass heading without a magnetometer —
    /// a fixed bearing, or 0/90/180/270 in turn (checks the cone, and that it turns while the
    /// dot stands still).
    static var fakeHeading: String? { env["WM_FAKE_HEADING"] }
    /// WM_FAKE_DEVICE_ORIENTATION=portrait|upsideDown|landscapeLeft|landscapeRight stands in for
    /// the pose the compass correction is computed from (checks that the cone stays on the
    /// user's facing when the phone is turned in the hand).
    static var fakeDeviceOrientation: String? { env["WM_FAKE_DEVICE_ORIENTATION"] }
    /// WM_START_PLANNER=1 opens the explorer's input sheet on launch.
    static var openPlanner: Bool { env["WM_START_PLANNER"] == "1" }
    /// WM_PLAN_MODE=loop|destination pre-selects the planner's mode.
    static var planMode: PlanMode? { env["WM_PLAN_MODE"].flatMap(PlanMode.init(rawValue:)) }
    /// WM_PLAN_KM=5 pre-fills the planner's distance.
    static var planKilometers: Double? { env["WM_PLAN_KM"].flatMap(Double.init) }
    /// WM_PLAN_AUTORUN=1 plans a route straight after launch (checks the whole path without
    /// touching the sheet).
    static var planAutoRun: Bool { env["WM_PLAN_AUTORUN"] == "1" }
    /// WM_PLAN_GO=1 taps Go as soon as a route has been planned, so the state the route stays
    /// in can be seen without a tap.
    static var planAutoGo: Bool { env["WM_PLAN_GO"] == "1" }
    /// WM_PLAN_SHAPE=0|0.5|1 pre-sets the explorer's shape (checks the wide/tight setting).
    static var planShape: Double? { env["WM_PLAN_SHAPE"].flatMap(Double.init) }
    /// WM_PLAN_ROUTES=1..5 pre-sets how many routes are offered.
    static var planRoutes: Int? { env["WM_PLAN_ROUTES"].flatMap(Int.init) }
    /// WM_PLAN_NEW=0.1..1 pre-sets the share of the route that should be new ground.
    static var planMinimumNew: Double? { env["WM_PLAN_NEW"].flatMap(Double.init) }
    /// WM_FAKE_PLAN=1 replaces MKDirections with a fixture, so the planner's UI can be
    /// exercised without a network.
    static var fakePlan: Bool { env["WM_FAKE_PLAN"] == "1" }
    /// WM_FAKE_PIN="lat,lon" drops the destination pin at launch.
    static var fakePin: CLLocationCoordinate2D? { coordinate(env["WM_FAKE_PIN"]) }
    /// WM_SELECT_PIN=1 opens the pin's info bubble at launch — the simulator offers no way to
    /// tap the map from the command line.
    static var selectPin: Bool { env["WM_SELECT_PIN"] == "1" }
    /// WM_FOCUS_SEARCH=1 puts the explorer's search field in focus at launch, so the room the
    /// keyboard leaves the panel can be seen (the simulator offers no way to type into it).
    static var focusSearch: Bool { env["WM_FOCUS_SEARCH"] == "1" }
    /// WM_PIN_DELETE=1 fires the bubble's bin a moment later, through the very delegate method
    /// the bin calls.
    static var pinDelete: Bool { env["WM_PIN_DELETE"] == "1" }

    /// WM_FAKE_LOCATION="lat,lon" publishes a fixed position (checks the dot).
    static var fakeLocation: CLLocationCoordinate2D? { coordinate(env["WM_FAKE_LOCATION"]) }

    private static func coordinate(_ raw: String?) -> CLLocationCoordinate2D? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    /// WM_FLIP_MODES=<seconds> switches the stored map style between explore and legacy every
    /// that many seconds, so the controls' own light/dark transition can be watched.
    static func startModeFlipIfRequested() {
        guard let raw = env["WM_FLIP_MODES"], let seconds = Double(raw), seconds > 0 else { return }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            let stored = UserDefaults.standard.string(forKey: MapMode.storedKey) ?? MapMode.stored.rawValue
            UserDefaults.standard.set(stored == MapMode.explore.rawValue ? MapMode.legacy.rawValue
                                                                       : MapMode.explore.rawValue,
                                      forKey: MapMode.storedKey)
        }
    }

    /// WM_ROTATE="landscapeRight,portrait" — request each orientation in turn, 4 s apart,
    /// starting 6 s after launch. The simulator offers no way to turn the device from the
    /// command line and there is no Simulator UI to drag, so the turn is driven from inside.
    static func startRotationIfRequested() {
        guard let raw = env["WM_ROTATE"] else { return }
        let steps = raw.split(separator: ",").map(String.init)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            var delay = 0.0
            for step in steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    requestOrientation(step)
                }
                delay += 4
            }
        }
    }

    private static func requestOrientation(_ step: String) {
        let mask: UIInterfaceOrientationMask
        switch step {
        case "portrait": mask = .portrait
        case "upsideDown": mask = .portraitUpsideDown
        case "landscapeLeft": mask = .landscapeLeft
        case "landscapeRight": mask = .landscapeRight
        case "landscape": mask = .landscape
        default: return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
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
    static var startMapMode: MapMode? { nil }
    static var startAppearance: MapAppearance? { nil }
    static var startJumpStyle: RouteJumpStyle? { nil }
    static var sampleJumps: Bool { false }
    static var openModes: Bool { false }
    static var tapAt: CGPoint? { nil }
    static var fakeHeading: String? { nil }
    static var fakeDeviceOrientation: String? { nil }
    static var openPlanner: Bool { false }
    static var planMode: PlanMode? { nil }
    static var planKilometers: Double? { nil }
    static var planAutoRun: Bool { false }
    static var planAutoGo: Bool { false }
    static var planShape: Double? { nil }
    static var planRoutes: Int? { nil }
    static var planMinimumNew: Double? { nil }
    static var fakePlan: Bool { false }
    static var fakePin: CLLocationCoordinate2D? { nil }
    static var selectPin: Bool { false }
    static var focusSearch: Bool { false }
    static var pinDelete: Bool { false }
    static var tapDelay: Double { 4 }
    static var hideCard: Bool { false }
    static var skipLocation: Bool { false }
    static var stressCopies: Int { 1 }
    static var stressSpread: Double { 0.035 }
    static var fakeLocation: CLLocationCoordinate2D? { nil }
    static func startRotationIfRequested() {}
    static func startModeFlipIfRequested() {}
    static var startSelection: RangeSelection? { nil }
#endif
}
