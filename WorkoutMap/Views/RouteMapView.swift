import SwiftUI
import MapKit
import CoreLocation

struct MapRouteLine: Equatable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor

    static func == (lhs: MapRouteLine, rhs: MapRouteLine) -> Bool { lhs.id == rhs.id }
}

// MARK: - Map tone

/// The flat grey the map is composited with to lose its colour, and the black that
/// dims it — the two values measured from the original app's map.
enum MapTone {
    static let desaturation = UIColor(white: 0.5, alpha: 1)
    static let dim = UIColor(white: 0, alpha: 0.20)
}

/// A full-screen tone pass that MapKit composites *inside* its own render pass.
///
/// The tone cannot be a `CALayer` above the map view any more: VectorKit renders the
/// tiles and every `MKOverlayRenderer` into one Metal layer, so a filter above that
/// layer greys the routes out as well (measured — they lost their category colour).
/// As an overlay it composites against the map alone, and everything MapKit draws
/// after it — the routes — keeps its colour.
final class ToneOverlay: NSObject, MKOverlay {
    let fill: UIColor
    let blend: CGBlendMode

    init(fill: UIColor, blend: CGBlendMode) {
        self.fill = fill
        self.blend = blend
        super.init()
    }

    var coordinate: CLLocationCoordinate2D {
        MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate
    }

    var boundingMapRect: MKMapRect { MKMapRect.world }
}

final class ToneOverlayRenderer: MKOverlayRenderer {
    init(tone: ToneOverlay) {
        super.init(overlay: tone)
        blendMode = tone.blend
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let tone = overlay as? ToneOverlay else { return }
        context.setFillColor(tone.fill.cgColor)
        context.fill(rect(for: mapRect))
    }
}

// MARK: - Routes

/// Every route of one colour in a single overlay, so a colour costs one draw call
/// no matter how many workouts are on screen.
final class RouteColorOverlay: MKMultiPolyline {
    let color: UIColor

    init(color: UIColor, polylines: [MKPolyline]) {
        self.color = color
        super.init(polylines)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Current position

/// The "you are here" marker. An annotation, so MapKit places it itself and it
/// stays glued to the map.
final class UserDotAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

final class UserDotView: MKAnnotationView {
    static let reuseIdentifier = "UserDotView"
    private static let diameter: CGFloat = 22

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        isUserInteractionEnabled = false
        layer.cornerRadius = Self.diameter / 2
        layer.borderWidth = 3.5
        layer.borderColor = UIColor(red: 199.0 / 255, green: 199.0 / 255, blue: 204.0 / 255, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(color: UIColor) { backgroundColor = color }
}

// MARK: - Map view

final class FittableMapView: MKMapView {
    var onLayout: (() -> Void)?
    /// The *window's* safe area, so the SwiftUI side can tell a screen with a system
    /// side rail (the Duo) from a normal one — the rail belongs to the window, not to
    /// this view, which is already laid out inside it.
    var onSafeAreaChange: ((UIEdgeInsets) -> Void)?
    /// The floating tab bar's capsule, as insets from the window's bottom edge to its own
    /// bottom and top edges, so the SwiftUI overlays can line up with the bar itself
    /// rather than with the safe area.
    var onTabBarInsets: ((_ bottom: CGFloat, _ top: CGFloat) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
        reportWindow()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportWindow()
    }

    /// Reported on every layout pass rather than on change: SwiftUI rebuilds this screen's
    /// state when the window's geometry changes, and a rebuilt `@State` would then never be
    /// told again. The receivers compare and only write on a real change, so this stays a
    /// no-op in the steady state.
    private func reportWindow() {
        guard let window else { return }
        onSafeAreaChange?(window.safeAreaInsets)
        guard let bar = FittableMapView.tabBar(in: window) else { return }
        let frame = bar.convert(bar.bounds, to: window)
        let foot = window.bounds.maxY
        let bottom = foot - frame.maxY
        let top = foot - frame.minY
        guard bottom.isFinite, top.isFinite else { return }
        onTabBarInsets?(bottom, top)
    }

    /// The floating bar is drawn by a private `UITabBar` subclass; its capsule container is
    /// the view whose edges the filters follow. A rotation can leave a parked copy of that
    /// capsule in the window at a stale position, so candidates are restricted to visible
    /// views of a plausible capsule size that sit near the window's bottom edge — and the
    /// lowest one wins. The full-height `UITabBar` itself and its buttons would both give
    /// the wrong edge, so the capsule container is preferred over them.
    private static func tabBar(in root: UIView) -> UIView? {
        let windowBounds = root.bounds
        func scan(nearBottomOnly: Bool) -> UIView? {
            var capsule: (view: UIView, maxY: CGFloat)?
            var best: (view: UIView, maxY: CGFloat)?
            func walk(_ view: UIView) {
                if !view.isHidden, view.alpha > 0.01 {
                    let name = String(describing: type(of: view))
                    if name.contains("TabBar") {
                        let frame = view.convert(view.bounds, to: root)
                        let plausible = frame.width >= 30 && frame.height >= 30
                            && frame.width <= 400 && frame.height <= 400
                        let inset = windowBounds.maxY - frame.maxY
                        if plausible, windowBounds.intersects(frame),
                           !nearBottomOnly || (inset >= 0 && inset <= 140) {
                            if name.contains("Platter") {
                                if capsule == nil || frame.maxY > capsule!.maxY {
                                    capsule = (view, frame.maxY)
                                }
                            } else if best == nil || frame.maxY > best!.maxY {
                                best = (view, frame.maxY)
                            }
                        }
                    }
                }
                for sub in view.subviews { walk(sub) }
            }
            walk(root)
            return capsule?.view ?? best?.view
        }
        return scan(nearBottomOnly: true) ?? scan(nearBottomOnly: false)
    }
}

// MARK: - SwiftUI wrapper

/// The map with the filtered routes on it.
///
/// Both are drawn by MapKit itself — the routes as `MKPolyline` overlays, the tone as
/// blend-mode overlays — so they live in the same render pass: panning, zooming and
/// rotating move them in lockstep with the tiles, without a single line of per-frame
/// code on the main thread. A view that is positioned from `visibleMapRect` callbacks
/// can never do that: VectorKit renders a frame ahead of the main thread, so such an
/// overlay visibly chases the map.
struct RouteMapView: UIViewRepresentable {
    /// A camera move to perform. Every `cameraToken` change re-runs the request, even
    /// when it repeats the previous one.
    enum Camera {
        /// Zoom out far enough to show the whole route set.
        case fit(MKMapRect)
        /// Centre on a coordinate — the locate button, or the newest route when the
        /// selected range holds no data at all.
        case center(CLLocationCoordinate2D, spanMeters: Double)
    }

    var routes: [MapRouteLine] = []
    var camera: Camera?
    var cameraToken: Int = 0
    var userLocation: CLLocationCoordinate2D?
    var userDotColor: UIColor = UIColor(red: 1, green: 199.0 / 255, blue: 3.0 / 255, alpha: 1)
    var onRegionChange: ((MKMapRect) -> Void)?
    var onUserInteraction: (() -> Void)?
    /// The window's safe-area insets, reported after layout and on orientation or
    /// fold changes.
    var onSafeAreaChange: ((UIEdgeInsets) -> Void)?
    /// The floating tab bar's capsule, as insets from the window's bottom edge to its own
    /// bottom and top edges.
    var onTabBarInsets: ((_ bottom: CGFloat, _ top: CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FittableMapView {
        let map = FittableMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MapImageRenderer.configuration()
        map.overrideUserInterfaceStyle = .dark
        // The camera fits into the view's layout margins, so the safe area would push a
        // fitted route set and a centred user location off centre — this screen draws the
        // map edge to edge and centres on the full view instead.
        map.insetsLayoutMarginsFromSafeArea = false
        map.backgroundColor = .black
        // Rotation on, tilt off: a two-finger turn keeps the routes aligned because
        // MapKit draws them, pitch would only fight the layout of the toolbar.
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.showsBuildings = false
        map.register(UserDotView.self, forAnnotationViewWithReuseIdentifier: UserDotView.reuseIdentifier)
        map.onLayout = { [weak coordinator = context.coordinator] in coordinator?.applyPendingCamera() }
        map.onSafeAreaChange = { [weak coordinator = context.coordinator] insets in
            // Deferred: the report arrives from a layout pass, and the receiver writes
            // SwiftUI state.
            DispatchQueue.main.async { coordinator?.parent.onSafeAreaChange?(insets) }
        }
        map.onTabBarInsets = { [weak coordinator = context.coordinator] bottom, top in
            // Deferred like the safe-area report: this arrives from a layout pass.
            DispatchQueue.main.async { coordinator?.parent.onTabBarInsets?(bottom, top) }
        }
        context.coordinator.map = map
        context.coordinator.installToneOverlays()
        context.coordinator.installInteractionObservers()
        return map
    }

    func updateUIView(_ map: FittableMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateRoutes()
        context.coordinator.updateUserDot()
        if context.coordinator.appliedCameraToken != cameraToken {
            context.coordinator.appliedCameraToken = cameraToken
            context.coordinator.pendingCamera = camera
            context.coordinator.applyPendingCamera()
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: FittableMapView?
        var parent: RouteMapView
        var appliedCameraToken = -1
        var pendingCamera: RouteMapView.Camera?

        private var toneOverlays: [ToneOverlay] = []
        private var routeOverlays: [RouteColorOverlay] = []
        /// Routes already turned into overlays, so a reload that adds routes one at a
        /// time costs one polyline per arrival instead of rebuilding the whole set.
        private var polylines: [String: MKPolyline] = [:]
        private var signature = ""
        private var dotAnnotation: UserDotAnnotation?

        init(_ parent: RouteMapView) { self.parent = parent }

        /// The tone arrives before any route, and MapKit draws overlays in the order
        /// they were added, so the routes land on top of it.
        func installToneOverlays() {
            guard let map else { return }
            toneOverlays = [ToneOverlay(fill: MapTone.desaturation, blend: .saturation),
                            ToneOverlay(fill: MapTone.dim, blend: .normal)]
            map.addOverlays(toneOverlays, level: .aboveLabels)
        }

        func installInteractionObservers() {
            guard let map else { return }
            for recognizer in [UIPanGestureRecognizer(target: self, action: #selector(handleGesture(_:))),
                               UIPinchGestureRecognizer(target: self, action: #selector(handleGesture(_:))),
                               UIRotationGestureRecognizer(target: self, action: #selector(handleGesture(_:)))] {
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                map.addGestureRecognizer(recognizer)
            }
        }

        @objc private func handleGesture(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .changed, .ended: parent.onUserInteraction?()
            default: break
            }
        }

        func applyPendingCamera() {
            guard let map, map.bounds.width > 1, map.bounds.height > 1 else { return }
            guard let camera = pendingCamera else { return }
            pendingCamera = nil
            switch camera {
            case .fit(let rect):
                map.setVisibleMapRect(rect, animated: true)
            case .center(let coordinate, let spanMeters):
                map.setRegion(MKCoordinateRegion(center: coordinate,
                                                 latitudinalMeters: spanMeters,
                                                 longitudinalMeters: spanMeters),
                              animated: true)
            }
        }

        // MARK: routes

        /// Rebuilds the overlays, and only when the route set changes.
        func updateRoutes() {
            guard let map else { return }
            var next = ""
            for line in parent.routes {
                next += line.id
                next += "|\(line.coordinates.count)|\(line.color.hashValue);"
            }
            guard next != signature else { return }
            signature = next

            var wanted: Set<String> = []
            for line in parent.routes where line.coordinates.count > 1 {
                wanted.insert(line.id)
                if polylines[line.id] == nil {
                    polylines[line.id] = MKPolyline(coordinates: line.coordinates,
                                                    count: line.coordinates.count)
                }
            }
            polylines = polylines.filter { wanted.contains($0.key) }

            var grouped: [(color: UIColor, polylines: [MKPolyline])] = []
            for line in parent.routes {
                guard let polyline = polylines[line.id] else { continue }
                if let index = grouped.firstIndex(where: { $0.color == line.color }) {
                    grouped[index].polylines.append(polyline)
                } else {
                    grouped.append((line.color, [polyline]))
                }
            }

            map.removeOverlays(routeOverlays)
            routeOverlays = grouped.map { RouteColorOverlay(color: $0.color, polylines: $0.polylines) }
            map.addOverlays(routeOverlays, level: .aboveLabels)
        }

        func updateUserDot() {
            guard let map else { return }
            guard let location = parent.userLocation else {
                if let dotAnnotation {
                    map.removeAnnotation(dotAnnotation)
                    self.dotAnnotation = nil
                }
                return
            }
            if let dotAnnotation {
                dotAnnotation.coordinate = location
                (map.view(for: dotAnnotation) as? UserDotView)?.apply(color: parent.userDotColor)
            } else {
                let annotation = UserDotAnnotation(coordinate: location)
                dotAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }

        // MARK: delegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is UserDotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: UserDotView.reuseIdentifier,
                                                             for: annotation)
            (view as? UserDotView)?.apply(color: parent.userDotColor)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tone = overlay as? ToneOverlay { return ToneOverlayRenderer(tone: tone) }
            guard let group = overlay as? RouteColorOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolylineRenderer(multiPolyline: group)
            renderer.strokeColor = group.color
            renderer.lineWidth = Metrics.routeWidth
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange?(mapView.visibleMapRect)
        }
    }
}

extension RouteMapView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
