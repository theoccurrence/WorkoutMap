import UIKit
import Combine

/// The system's own light/dark setting, which the map follows while the appearance setting is
/// `MapAppearance.system`.
///
/// The app is pinned to dark (see `WorkoutMapApp`), so every trait it can see — the window, the
/// scene, `UITraitCollection.current` — reports dark whatever the phone is set to. The
/// *screen's* trait is the one that still follows the system, which is why it is read through
/// the window scene's screen rather than through the app's own view hierarchy.
///
/// Nothing publishes that trait: `UIScreen` is not `UITraitChangeObservable`, and KVO on its
/// `traitCollection` reports the value once and never again (checked). The app can neither wait
/// for the next activation, which is what it did: the setting is changed in Control Center or
/// in Settings, both of which leave the app *inactive but still drawing*, and Maps turns while
/// Control Center is still open. So the screen is read on a short poll for as long as the app
/// is on screen, and once more when it comes back — one property read every `pollInterval`,
/// which is what an instant, animated answer to the system's own switch costs.
final class SystemAppearance: ObservableObject {
    static let shared = SystemAppearance()

    @Published private(set) var style: UIUserInterfaceStyle

    private var observers: [NSObjectProtocol] = []
    private var poll: Timer?

    /// How often the screen is read while the app is on screen.
    private static let pollInterval: TimeInterval = 0.2

    private init() {
        style = SystemAppearance.currentStyle
        let center = NotificationCenter.default
        // Coming back: read the screen at once — the poll has just been stopped.
        for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
                self?.startPolling()
            })
        }
        // Leaving: the setting can only be changed while the app is away, so there is nothing
        // left to read.
        for name in [UIApplication.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stopPolling()
            })
        }
        startPolling()
    }

    deinit {
        poll?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// The style the app's screen is showing. The scene's screen carries it, and it is the one
    /// trait the app's dark pinning does not reach.
    private static var currentStyle: UIUserInterfaceStyle {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.traitCollection.userInterfaceStyle ?? .dark
    }

    private func startPolling() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// Re-reads the screen's style and publishes only on a real change.
    private func refresh() {
        let current = SystemAppearance.currentStyle
        guard current != style else { return }
        style = current
    }
}
