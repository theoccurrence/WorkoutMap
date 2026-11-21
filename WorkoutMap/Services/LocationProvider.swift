import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorized = false
    /// The way the **user** faces, in degrees from true North, ready to draw: the compass
    /// reading turned back by however far the device has been rotated in the hand, so that
    /// turning the phone does not turn the cone (see `correction(for:)`). `nil` until the
    /// receiver has a reading.
    @Published private(set) var heading: CLLocationDirection?

    /// The compass reading as it arrives: referenced to the *top of the device*, which is what
    /// `CLHeading` reports, and therefore not yet the way the user faces.
    private var rawHeading: CLLocationDirection?
    /// The pose the correction is computed for. Flat poses carry no direction — the top edge
    /// could point anywhere — so the last one that did is kept.
    private var pose: UIDeviceOrientation = .portrait
    private var orientationObserver: NSObjectProtocol?

    /// The direction the last fix was travelling in, when the receiver reports one (it reports
    /// -1 while it cannot) and the fix is current — a receiver that has stopped delivering
    /// must not leave the cone pointing down the last road it saw.
    var course: CLLocationDirection? {
        guard let location, location.course >= 0,
              Date().timeIntervalSince(location.timestamp) < 5 else { return nil }
        return location.course
    }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // The most the receiver has to give: the navigation accuracy (the highest rate it
        // will hand out), no distance filter (every fix is passed on instead of the ones a
        // 5 m filter lets through), and no automatic pause. What arrives is still around one
        // fix a second — that is the receiver's own rate, a phone's GPS has no more — which
        // is why the map walks the dot between fixes instead of waiting for the next one
        // (see `RouteMapView.Coordinator.updateUserDot`).
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        // A degree of change is enough to send a new heading: the cone is smoothed on the
        // display's clock anyway (`UserDotView.stepCone`), and a coarser filter only costs the
        // target a little freshness while saving the screen a rebuild per degree of jitter.
        manager.headingFilter = 1
    }

    /// Recomputes the facing from the last compass reading and the current pose.
    private func refreshHeading() {
        updatePose()
        guard let rawHeading else { return }
        let turned = rawHeading + Self.correction(for: pose)
        let value = (turned + 360).truncatingRemainder(dividingBy: 360)
        // Half a degree is below what the eye can follow, and every publication rebuilds the map
        // screen: skipping the ones that small keeps the compass from costing frames.
        if let heading {
            let change = abs((value - heading + 540).truncatingRemainder(dividingBy: 360) - 180)
            guard change >= 0.5 else { return }
        }
        heading = value
    }

    /// The pose the device is held in, ignoring the flat ones.
    private func updatePose() {
        let current = DebugLaunch.fakeDeviceOrientation.flatMap(Self.pose(named:))
            ?? UIDevice.current.orientation
        switch current {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight: pose = current
        default: break
        }
    }

    private static func pose(named name: String) -> UIDeviceOrientation? {
        switch name {
        case "portrait": return .portrait
        case "portraitUpsideDown", "upsideDown": return .portraitUpsideDown
        case "landscapeLeft": return .landscapeLeft
        case "landscapeRight": return .landscapeRight
        default: return nil
        }
    }

    /// How far the device has been turned **in place** from the pose its display is built for,
    /// which is the amount `CLHeading` is off by: it reports the bearing of the top of the
    /// device, and a phone turned sideways in the hand has its top edge pointing sideways while
    /// its user still faces the same way. Portrait is the natural pose of both of the Duo's
    /// displays — unfolded, the inner one is merely *laid out* wide while the device itself
    /// stays upright — so nothing is added there; the two landscape poses need the device's
    /// own rotation back, and an upside-down phone half a turn.
    private static func correction(for pose: UIDeviceOrientation) -> CLLocationDirection {
        switch pose {
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        case .portraitUpsideDown: return 180
        default: return 0
        }
    }

    func start() {
        // `CLHeading` is referenced to the top of the device, so the pose has to be watched:
        // a phone turned sideways in the hand would otherwise point the cone 90° away from the
        // way its user faces, and it would stay there until the next reading.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshHeading() }
        }
#if DEBUG
        if let fake = DebugLaunch.fakeHeading {
            // A compass without a magnetometer (the simulator, or a test drive): a fixed
            // bearing, or 0/90/180/270 in turn so the cone can be watched turning while the
            // dot stands still.
            if let degrees = CLLocationDirection(fake) {
                rawHeading = degrees
            } else if fake == "cycle" {
                rawHeading = 0
                Task { @MainActor in
                    var angle: CLLocationDirection = 0
                    while true {
                        try? await Task.sleep(for: .seconds(2))
                        angle = (angle + 90).truncatingRemainder(dividingBy: 360)
                        self.rawHeading = angle
                        self.refreshHeading()
                    }
                }
            }
            refreshHeading()
        }
        if let fake = DebugLaunch.fakeLocation {
            authorized = true
            location = CLLocation(latitude: fake.latitude, longitude: fake.longitude)
            return
        }
#endif
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        // The magnetometer, for the cone. A receiver without one reports a failure, which the
        // delegate ignores; the map then falls back to the direction of travel.
        manager.startUpdatingHeading()
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
            if self.authorized {
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy means the reading is unusable; `trueHeading` is negative when the
        // receiver cannot correct the magnetometer against true North.
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.rawHeading = value
            self.refreshHeading()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
