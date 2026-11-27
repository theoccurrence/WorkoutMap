import Foundation
import MapKit
import UIKit

/// The five map styles the map screen offers: Apple Maps' own four, in its own order, plus
/// `legacy` — the app's original grey map — as the fifth.
///
/// MapKit has no single switch per mode, so each entry is the closest configuration it does
/// offer; `configuration()` spells the mapping out.
enum MapMode: String, CaseIterable, Identifiable {
    case explore, driving, transit, satellite, legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Explore"
        case .driving: return "Driving"
        case .transit: return "Transit"
        case .satellite: return "Satellite"
        case .legacy: return "Legacy"
        }
    }

    /// Where the map screen keeps the style it opens with.
    static let storedKey = "mapMode"

    /// Whether Satellite draws its labels — roads, place names — over the imagery. On by default,
    /// the way Maps' own Satellite mode starts; the toggle in the map modes panel writes it.
    static let satelliteLabelsKey = "satelliteLabels"
    static var satelliteLabels: Bool {
        UserDefaults.standard.object(forKey: satelliteLabelsKey) as? Bool ?? true
    }

    /// The style the map opens with unless the user picked another one.
    ///
    /// The shipped default is `explore` — Maps' own standard map, in the app's own layer of routes
    /// over it. It used to be `legacy`, the grey map the app shipped with, which is still there as
    /// the fifth style rather than the one a fresh install opens on.
    static var stored: MapMode {
        guard let raw = UserDefaults.standard.string(forKey: storedKey) else { return .explore }
        return MapMode(rawValue: raw) ?? .explore
    }

    /// The MapKit configuration behind each mode:
    ///
    /// * `explore` — the standard map with its normal emphasis and its points of interest.
    /// * `driving` — the same, with live traffic.
    /// * `transit` — the same, with the points of interest cut down to stations and stops.
    ///   MapKit draws the transit lines itself on the standard map; it has no switch for
    ///   them, so the stations are what is left to emphasise.
    /// * `satellite` — imagery without labels, as Maps' own Satellite mode. The imagery is the one
    ///   style whose **elevation** has to be `realistic` rather than `flat`: the standard map is drawn
    ///   with its buildings whatever the elevation says, so a two-finger tilt lifts Explore, Driving,
    ///   Transit and Legacy into 3D on its own, while a `flat` imagery map is held at 0° — it is the
    ///   one mode that would not tilt at all (measured: the same camera, pitched 55°, leaves an imagery
    ///   map flat and lifts a standard one to 3D). `realistic` is what lets MapKit draw its 3D imagery
    ///   and terrain, where the region has any; from straight above the two look the same.
    /// * `legacy` — the style the app shipped with: the muted standard map with every point
    ///   of interest excluded, greyed out by the tone pass (see `usesTone`).
    func configuration(satelliteLabels: Bool = MapMode.satelliteLabels) -> MKMapConfiguration {
        switch self {
        case .explore:
            return MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        case .driving:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            config.showsTraffic = true
            return config
        case .transit:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            config.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            return config
        case .satellite:
            // Hybrid is the imagery *with* the labels layer — roads, places — which is what Maps'
            // Satellite mode shows by default; imagery alone is the bare photograph.
            return satelliteLabels
                ? MKHybridMapConfiguration(elevationStyle: .realistic)
                : MKImageryMapConfiguration(elevationStyle: .realistic)
        case .legacy:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            return config
        }
    }

    /// Whether the map is drawn with a `realistic` elevation — the satellite imagery, which needs it for
    /// its 3D. Read from the configuration itself, so the two cannot drift apart, and asked by
    /// `RouteLineRenderer`, whose own stroke-width conversion MapKit gets wrong on exactly this style.
    var usesRealisticElevation: Bool {
        configuration().elevationStyle == .realistic
    }

    /// Whether the map keeps the app's grey: the two blend-mode overlays over the live
    /// map (`ToneOverlay`) and the same tone applied to the pixels of a snapshot. Only the
    /// legacy style has it — the other four are the map as MapKit draws it.
    var usesTone: Bool { self == .legacy }

    /// The tile the "Map Modes" panel draws for this style, in the appearance the map is
    /// being drawn in — Maps' own artwork for Explore, Driving, Transit and Satellite, and for
    /// `legacy` the grey Explore tile, which is what the app's own map looks like. Bundled
    /// rather than snapshotted: five `MKMapSnapshotter` runs took a moment to arrive every
    /// time the panel opened, and the artwork is what Maps itself shows.
    func artwork(for style: UIUserInterfaceStyle) -> UIImage? {
        let name: String
        switch self {
        case .explore: name = style == .light ? "MapModeExploreLight" : "MapModeExploreDark"
        case .driving: name = style == .light ? "MapModeDrivingLight" : "MapModeDrivingDark"
        case .transit: name = style == .light ? "MapModeTransitLight" : "MapModeTransitDark"
        case .satellite: name = "MapModeSatellite"
        case .legacy: name = "MapModeLegacy"
        }
        return UIImage(named: name)
    }
}

/// How the map is drawn: in the system's own light or dark style, or pinned to one of the two.
///
/// The app itself is dark (see `WorkoutMapApp`); this governs the *map* alone. `legacy` — the
/// grey map the app shipped with — is not affected either way and stays dark.
enum MapAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Where the settings keep it.
    static let storedKey = "mapAppearance"

    /// What the map opens with: the system's own setting, so it follows the phone until the
    /// user pins one.
    static var stored: MapAppearance {
        guard let raw = UserDefaults.standard.string(forKey: storedKey) else { return .system }
        return MapAppearance(rawValue: raw) ?? .system
    }

    /// The interface style a map is drawn in. `system` hands the system's own style back; the
    /// two pinned entries override it.
    func interfaceStyle(system: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        switch self {
        case .system: return system
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The style one map mode is drawn in. `legacy` is the grey map the app shipped with and
    /// keeps the dark style it has always had whatever this says; every other mode follows it.
    func interfaceStyle(for mode: MapMode, system: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        mode == .legacy ? .dark : interfaceStyle(system: system)
    }
}
