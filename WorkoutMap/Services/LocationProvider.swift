import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorized = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func start() {
#if DEBUG
        if let fake = DebugLaunch.fakeLocation {
            authorized = true
            location = CLLocation(latitude: fake.latitude, longitude: fake.longitude)
            return
        }
#endif
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
            if self.authorized { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
