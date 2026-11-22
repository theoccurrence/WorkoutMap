import SwiftUI
import MapKit
import CoreLocation

struct MapRouteLine: Equatable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
    /// The stroke width. The workout routes all share the measured `Metrics.routeWidth`; a
    /// planned route is drawn wider, with a casing under it (see `MapTabView.plannedLines`).
    var width: CGFloat = Metrics.routeWidth
    /// The dash pattern, in points, for a line that stands for ground the user did not cover —
    /// a GPS jump, drawn as a row of dots (`RouteJump`). `nil` is a solid line.
    var dash: [CGFloat]? = nil

    static func == (lhs: MapRouteLine, rhs: MapRouteLine) -> Bool { lhs.id == rhs.id }
}

extension MapRouteLine {
    /// One workout route as the lines it is drawn as: the stretches the user walked, in the
    /// category's colour, and each leg one of the two jump rules caught, in that rule's own tone
    /// (`tones`) and style (`JumpRules`). A leg's dots are measured against `routeWidth`, so they
    /// follow the weight the routes are drawn at rather than sit on a weight of their own.
    ///
    /// Legs the user erased in the route editor (`erased`) are left out entirely — walked legs and
    /// jump legs alike, so a dotted line the user erased goes as readily as a stretch of the route.
    ///
    /// Every line's id is the workout's own with a suffix; `Coordinator.baseRouteID` cuts the
    /// suffix off again, so a tap anywhere on the route picks that workout.
    static func lines(for workout: Workout,
                      route: WorkoutRoute,
                      rules: JumpRules,
                      color: UIColor,
                      tones: JumpTones,
                      erased: EraseEdits = .empty,
                      routeWidth: CGFloat = Metrics.routeWidth) -> [MapRouteLine] {
        let drawing = route.drawing(rules, erased: erased)
        var lines = drawing.walked.enumerated().map { index, coordinates in
            MapRouteLine(id: "\(workout.id.uuidString)#\(index)",
                         coordinates: coordinates,
                         color: color,
                         width: routeWidth)
        }
        for (index, leg) in drawing.legs.enumerated() {
            switch rules.style(for: leg.kind) {
            case .hidden:
                continue
            case .dotted:
                lines.append(MapRouteLine(id: "\(workout.id.uuidString)#\(leg.kind.rawValue)\(index)",
                                          coordinates: leg.coordinates,
                                          color: tones.uiColor(for: leg.kind),
                                          width: RouteJump.dotDiameter(routeWidth: routeWidth),
                                          dash: RouteJump.dotDash(routeWidth: routeWidth)))
            case .solid:
                lines.append(MapRouteLine(id: "\(workout.id.uuidString)#\(leg.kind.rawValue)\(index)",
                                          coordinates: leg.coordinates,
                                          color: tones.uiColor(for: leg.kind),
                                          width: routeWidth))
            }
        }
        return lines
    }
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
    /// Off in every map mode but `legacy`. The overlay stays installed and its renderer
    /// simply draws nothing: MapKit draws the overlays of one level in the order they were
    /// added, so a tone pass re-added after a mode change would land *above* the routes and
    /// grey those out with it.
    var active: Bool

    init(fill: UIColor, blend: CGBlendMode, active: Bool) {
        self.fill = fill
        self.blend = blend
        self.active = active
        super.init()
    }

    var coordinate: CLLocationCoordinate2D {
        MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate
    }

    var boundingMapRect: MKMapRect { MKMapRect.world }
}

/// Draws a jump as a row of dots, itself.
///
/// MapKit's own dashed stroke does not hold a size against the map's zoom. Measured with the
/// camera pinned over the *same* routes (`WM_ZOOM_SPAN`) the dots came out ~4 px at a 1.5 km
/// span and ~10 px at a 40 km one, while the route's solid line stayed the same width at every
/// span — so the dots grow past the line they interrupt. This renderer strokes the dots at a
/// size the zoom cannot move instead, and the coordinator asks it to redraw when the zoom
/// actually changed.
///
/// It strokes only the legs of the tile it is handed (`legs`), one leg at a time: a tile is
/// asked for again every time a pan brings a new one in, and paying for every leg on the map each
/// time is what made the map crawl. Gathered into a single path instead, Core Graphics works out
/// the union of every dot in the tile, which at the wide strokes a world-level zoom asks for
/// (a dot several kilometres across in map points) measured 200 ms a tile against 8 ms for the
/// same dots stroked one leg at a time — so a tile costs its own dots, stroked as they were.
final class JumpDotsRenderer: MKOverlayRenderer {
    private let color: UIColor
    /// The dot's diameter, in points on the screen.
    private let diameter: CGFloat
    /// The distance between two dot centres, in the same points.
    private let spacing: CGFloat
    /// Every leg of the overlay with the rectangle it covers. MapKit hands the renderer one
    /// *tile* at a time, so a tile that stroked the whole overlay again paid for every leg on
    /// the map — 8–11 ms measured at a few thousand legs, on each tile, on every frame a pan
    /// brought a new tile in — no matter how little of the route set the tile held. The legs a
    /// tile can actually reach are picked out first instead.
    private let legs: [(polyline: MKPolyline, bounds: MKMapRect)]

    override init(overlay: MKOverlay) {
        let jump = overlay as? RouteColorOverlay
        color = jump?.color ?? RouteJump.distanceTone
        diameter = jump?.width ?? RouteJump.dotDiameter(routeWidth: Metrics.routeWidth)
        spacing = diameter * RouteJump.spacingScale
        legs = (jump?.polylines ?? [])
            .filter { $0.pointCount > 1 }
            .map { ($0, $0.boundingMapRect) }
        super.init(overlay: overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard !legs.isEmpty, diameter > 0, spacing > 0 else { return }
        // The renderer's own space is map points, and MapKit hands a *tile* over — measured, a
        // tile is drawn at twice the display's resolution (a dot asked for at 1.45 pt came out
        // at ~1.3 px per point of it) — so a size that should be `diameter` points on the screen
        // is twice the diameter divided by the zoom scale. The same goes for the gap between two
        // dots: a zero-length dash with a round cap is one circle, and the second length keeps
        // two of them apart.
        let scale = 2 / CGFloat(zoomScale)
        // A dot reaches half a diameter either side of the leg it sits on, so a leg is kept while
        // that much of it can still land inside the tile.
        let reach = Double(diameter * scale)
        context.saveGState()
        // Clipped to the tile, like every other tile drawing MapKit makes: a dot is carried by
        // the tiles it touches and never drawn outside them.
        context.clip(to: rect(for: mapRect))
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(diameter * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: [0.01 * scale, spacing * scale])
        for leg in legs where leg.bounds.insetBy(dx: -reach, dy: -reach).intersects(mapRect) {
            let path = CGMutablePath()
            let points = leg.polyline.points()
            for index in 0..<leg.polyline.pointCount {
                let dot = point(for: points[index])
                if index == 0 { path.move(to: dot) } else { path.addLine(to: dot) }
            }
            context.addPath(path)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])
        context.restoreGState()
    }
}

final class ToneOverlayRenderer: MKOverlayRenderer {
    init(tone: ToneOverlay) {
        super.init(overlay: tone)
        blendMode = tone.blend
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let tone = overlay as? ToneOverlay, tone.active else { return }
        context.setFillColor(tone.fill.cgColor)
        context.fill(rect(for: mapRect))
    }
}

// MARK: - Routes

/// Every route of one colour in a single overlay, so a colour costs one draw call
/// no matter how many workouts are on screen.
final class RouteColorOverlay: MKMultiPolyline {
    let color: UIColor
    let width: CGFloat
    /// The dash pattern in points, or `nil` for a solid line — see `MapRouteLine.dash`.
    let dash: [CGFloat]?

    init(color: UIColor, width: CGFloat, dash: [CGFloat]?, polylines: [MKPolyline]) {
        self.color = color
        self.width = width
        self.dash = dash
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

/// The destination pin the user drops on the map — one at a time, as in Maps: a new pin
/// replaces the old one.
///
/// `title` is what the pin's info bubble heads with — the name the geocoder resolved for it.
/// The address and the distance are not here: MapKit drops an annotation's subtitle once the
/// callout has a `detailCalloutAccessoryView`, so both live in that instead.
final class DestinationPinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(coordinate: CLLocationCoordinate2D, title: String?) {
        self.coordinate = coordinate
        self.title = title
        super.init()
    }
}

/// The dropped pin's own look: a red balloon, the marker Maps drops, with an info bubble that
/// carries the address, how far away it is, and a bin.
final class DestinationPinView: MKMarkerAnnotationView {
    static let reuseIdentifier = "DestinationPinView"

    /// The bubble's two lines under the place name. Written in place rather than by re-laying the
    /// callout out, so walking towards the pin does not make the bubble flicker once a second.
    private let addressLabel = UILabel()
    private let distanceLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        markerTintColor = .systemRed
        glyphTintColor = .white
        animatesWhenAdded = true
        displayPriority = .required
        canShowCallout = true
        rightCalloutAccessoryView = DestinationPinView.removeButton()
        for label in [addressLabel, distanceLabel] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            // A dynamic colour, so it follows the callout's own light or dark bubble.
            label.textColor = .secondaryLabel
        }
        let lines = UIStackView(arrangedSubviews: [addressLabel, distanceLabel])
        lines.axis = .vertical
        lines.spacing = 2
        detailCalloutAccessoryView = lines
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Where the pin is, and how far away that is right now — `nil` distance while there is no
    /// fix, `nil` address while the geocoder has not answered yet.
    func apply(address: String?, distance: Double?) {
        addressLabel.text = address
        addressLabel.isHidden = (address ?? "").isEmpty
        distanceLabel.text = distance.map(Fmt.distanceAway)
        distanceLabel.isHidden = distance == nil
    }

    private static func removeButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = .systemRed
        button.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        button.accessibilityLabel = "Remove pin"
        return button
    }
}

/// The "you are here" marker: the measured dot, and — as Maps draws it — a translucent cone in
/// front of it showing which way the user is facing, in the colour of the selected category.
final class UserDotView: MKAnnotationView {
    static let reuseIdentifier = "UserDotView"
    /// The dot itself, measured from the original app: 22 pt with a 3.5 pt ring.
    private static let diameter: CGFloat = 22
    private static let ringColor = UIColor(red: 199.0 / 255, green: 199.0 / 255, blue: 204.0 / 255, alpha: 1)
    /// The cone: long enough to read as a direction at a glance, narrow enough not to look
    /// like a slice of pie, and fading out instead of stopping at a hard edge.
    private static let coneLength: CGFloat = 34
    private static let coneHalfAngle: CGFloat = 26
    private static let coneAlpha: CGFloat = 0.45
    /// The view is as large as the cone needs. MapKit keeps its *centre* on the coordinate, so
    /// the dot itself does not move by a pixel.
    private static let box: CGFloat = (coneLength + diameter / 2) * 2

    private let coneHolder = CALayer()
    private let cone = CAGradientLayer()
    private let dot = CALayer()
    /// The angle the cone is drawn at and the angle it is heading for, both unwrapped: 350° to
    /// 10° has to turn 20° and not 340.
    private var drawnAngle: CGFloat = 0
    private var targetAngle: CGFloat = 0
    private var coneShown = false
    /// The cone is turned on the display's own clock instead of in one animation per heading.
    /// The compass reports in steps and a quick turn arrives in a handful of them; restarting a
    /// fixed 0.2 s animation per step is what made it look choppy. This walks the drawn angle
    /// towards the target every frame instead, so a step is caught up with smoothly and a late
    /// one is still reached.
    private var coneLink: CADisplayLink?
    /// 63 % of the remaining angle is covered in this long; short enough to feel immediate.
    private static let coneTau: CGFloat = 0.12

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.box, height: Self.box)
        isUserInteractionEnabled = false

        // The cone: a radial gradient from the dot outwards, clipped to a sector that points up
        // at zero rotation and is then turned by `apply(direction:cameraHeading:)`.
        coneHolder.frame = bounds
        coneHolder.isHidden = true
        cone.type = .radial
        cone.frame = bounds
        cone.startPoint = CGPoint(x: 0.5, y: 0.5)
        let radius = Self.coneLength / Self.box
        cone.endPoint = CGPoint(x: 0.5 + radius, y: 0.5)
        let centre = CGPoint(x: Self.box / 2, y: Self.box / 2)
        let sector = UIBezierPath()
        sector.move(to: centre)
        sector.addArc(withCenter: centre,
                      radius: Self.coneLength,
                      startAngle: -.pi / 2 - Self.coneHalfAngle * .pi / 180,
                      endAngle: -.pi / 2 + Self.coneHalfAngle * .pi / 180,
                      clockwise: true)
        sector.close()
        let mask = CAShapeLayer()
        mask.path = sector.cgPath
        mask.fillColor = UIColor.black.cgColor
        cone.mask = mask
        coneHolder.addSublayer(cone)

        dot.frame = CGRect(x: (Self.box - Self.diameter) / 2,
                           y: (Self.box - Self.diameter) / 2,
                           width: Self.diameter,
                           height: Self.diameter)
        dot.cornerRadius = Self.diameter / 2
        dot.borderWidth = 3.5
        dot.borderColor = Self.ringColor.cgColor

        layer.addSublayer(coneHolder)
        layer.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(color: UIColor) {
        dot.backgroundColor = color.cgColor
        cone.colors = [color.withAlphaComponent(Self.coneAlpha).cgColor,
                       color.withAlphaComponent(0).cgColor]
    }

    /// Points the cone the way the user faces, on screen: `direction` is degrees from true
    /// North, the camera's own heading turns it with the map. `nil` — the direction is not
    /// known — takes the cone off the screen.
    func apply(direction: CLLocationDirection?, cameraHeading: CLLocationDirection) {
        guard let direction else {
            if coneShown {
                coneShown = false
                coneHolder.isHidden = true
            }
            stopConeLink()
            return
        }
        let target = CGFloat((direction - cameraHeading) * .pi / 180)
        var delta = target - targetAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        targetAngle += delta
        if !coneShown {
            coneShown = true
            coneHolder.isHidden = false
            // The first appearance is placed, not turned: there is no angle to come from.
            drawnAngle = targetAngle
            applyConeAngle()
        }
        // A standing heading jitters by a fraction of a degree; a link for that is wasted work.
        if abs(delta) > 0.0005 { startConeLink() }
    }

    /// One frame of the turn: the drawn angle covers a fixed share of what is left of the way
    /// to the target, so the cone moves at the display's rate whatever the compass does.
    @objc private func stepCone(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        let share = 1 - exp(-CGFloat(dt) / Self.coneTau)
        drawnAngle += (targetAngle - drawnAngle) * share
        if abs(targetAngle - drawnAngle) < 0.0015 {
            drawnAngle = targetAngle
            applyConeAngle()
            stopConeLink()
            return
        }
        applyConeAngle()
    }

    private func applyConeAngle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coneHolder.transform = CATransform3DMakeRotation(drawnAngle, 0, 0, 1)
        CATransaction.commit()
    }

    private func startConeLink() {
        guard coneLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepCone(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        coneLink = link
    }

    private func stopConeLink() {
        coneLink?.invalidate()
        coneLink = nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // A display link retains its target; one left scheduled would keep this view alive.
        if superview == nil { stopConeLink() }
    }
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
        guard window != nil else { return }
        reportWindow()
    }

    /// Reported on every layout pass rather than on change: SwiftUI rebuilds this screen's
    /// state when the window's geometry changes, and a rebuilt `@State` would then never be
    /// told again. The receivers compare and only write on a real change, so this stays a
    /// no-op in the steady state.
    private func reportWindow() {
        guard let window else { return }
        onSafeAreaChange?(window.safeAreaInsets)
        if let bar = FittableMapView.tabBar(in: window) {
            let frame = bar.convert(bar.bounds, to: window)
            let foot = window.bounds.maxY
            let bottom = foot - frame.maxY
            let top = foot - frame.minY
            guard bottom.isFinite, top.isFinite else { return }
            onTabBarInsets?(bottom, top)
        }
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
    /// The explorer's planned route and its alternates. Drawn **after** the workout routes, so
    /// a planned route is never hidden under one, and with the width each line carries.
    var planned: [MapRouteLine] = []
    /// The destination pin the user dropped, if any. One at a time.
    var pin: CLLocationCoordinate2D?
    /// What the pin's info bubble says: what the place is called, and where it is.
    var pinTitle: String?
    var pinSubtitle: String?
    /// The bin in that bubble.
    var onPinDelete: (() -> Void)?
    var camera: Camera?
    var cameraToken: Int = 0
    /// The map style — see `MapMode`. Everything but `legacy` is the map as MapKit draws it.
    var mode: MapMode = .legacy
    /// The style the map draws in: light or dark, resolved from the settings (`MapAppearance`).
    /// `legacy` is drawn dark whatever this says, since it is the grey map the app shipped with.
    var interfaceStyle: UIUserInterfaceStyle = .dark
    var userLocation: CLLocationCoordinate2D?
    /// The way the device faces, in degrees from true North *as measured from the top of the
    /// device* — the map turns it to match the screen. `nil` when the receiver has no heading.
    var userHeading: CLLocationDirection?
    /// The direction the last fix travelled in, when the receiver reports one.
    var userCourse: CLLocationDirection?
    var userDotColor: UIColor = UIColor(red: 1, green: 199.0 / 255, blue: 3.0 / 255, alpha: 1)
    var onRegionChange: ((MKMapRect) -> Void)?
    var onUserInteraction: (() -> Void)?
    /// A tap on the map: the id of the route the tap landed on, or `nil` when it landed on the
    /// map itself. The routes are MapKit overlays with no tap target of their own, so the tap is
    /// resolved against the route geometry (see `Coordinator.routeID(near:within:)`).
    var onRouteTap: ((String?) -> Void)?
    /// A long press on the map: where it landed, so the explorer can drop its destination pin
    /// there, as Maps does.
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    /// A tap that landed on one of the planned routes: which one, so tapping a washed-out
    /// alternate on the map makes it the one — as tapping an alternate card does in Maps.
    var onPlannedTap: ((Int) -> Void)?
    /// The eraser's brush radius in points, or `nil` while the map is not being edited.
    ///
    /// With a brush up, one finger erases: MapKit's own pan is parked (it cannot be told to leave a
    /// single finger alone) and the coordinator adds two recognizers — a one-finger drag that
    /// reports an eraser stroke, and a two-finger drag that moves the map by setting its region. A
    /// pinch and a rotation are untouched, so the map still zooms and turns as it does elsewhere.
    /// See `Coordinator.updateEraser`.
    var eraserRadius: CGFloat?
    /// One step of an eraser stroke: the segment the finger just travelled — `from` is `nil` for
    /// the stroke's first point — and the brush's radius in the map's own units at that zoom.
    /// The radii are what the eraser measures against: a brush of a fixed size *on the screen*
    /// covers more ground the further the map is zoomed out, and the caller needs the same number
    /// the finger covers.
    var onErase: ((_ from: MKMapPoint?, _ to: MKMapPoint, _ radius: Double) -> Void)?
    /// Where the brush is on the screen, so the editor can draw it under the finger, and `nil`
    /// when the finger left the map.
    var onEraseCursor: ((CGPoint?) -> Void)?
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
        map.preferredConfiguration = mode.configuration()
        // MapKit draws its standard map (and its imagery labels) in the interface style it is
        // handed; the app is pinned to dark, so the map carries its own.
        map.overrideUserInterfaceStyle = interfaceStyle
        // The camera fits into the view's layout margins, so the safe area would push a
        // fitted route set and a centred user location off centre — this screen draws the
        // map edge to edge and centres on the full view instead.
        map.insetsLayoutMarginsFromSafeArea = false
        // The colour the tiles are laid on while they load, resolved against the map's own
        // style: black for the dark map, white for the light one.
        map.backgroundColor = .systemBackground
        // Rotation on, tilt off: a two-finger turn keeps the routes aligned because
        // MapKit draws them, pitch would only fight the layout of the toolbar.
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.showsBuildings = false
        map.register(UserDotView.self, forAnnotationViewWithReuseIdentifier: UserDotView.reuseIdentifier)
        map.register(DestinationPinView.self,
                     forAnnotationViewWithReuseIdentifier: DestinationPinView.reuseIdentifier)
        map.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.applyPendingCamera()
            // A layout pass means the window may have turned, and the device heading is
            // measured from the top of the device — what it means on screen has changed.
            coordinator?.applyDotDirection()
        }
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
        context.coordinator.appliedInterfaceStyle = interfaceStyle
        context.coordinator.installToneOverlays()
        context.coordinator.installInteractionObservers()
        context.coordinator.updateEraser()
#if DEBUG
        // WM_TAP_AT — see `DebugLaunch.tapAt`. The tap goes through the path the recognizer
        // uses, so the hit-test and the reporting are the ones that ship.
        if let point = DebugLaunch.tapAt {
            DispatchQueue.main.asyncAfter(deadline: .now() + DebugLaunch.tapDelay) { [weak coordinator = context.coordinator] in
                coordinator?.reportRouteTap(at: point)
            }
        }
        context.coordinator.runEraseProbeIfRequested()
#endif
        return map
    }

    func updateUIView(_ map: FittableMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAppearance()
        context.coordinator.updateMode()
        context.coordinator.updateEraser()
        context.coordinator.updateRoutes()
        context.coordinator.updatePin()
        context.coordinator.updateUserDot()
        if context.coordinator.appliedCameraToken != cameraToken {
            context.coordinator.appliedCameraToken = cameraToken
            context.coordinator.pendingCamera = camera
            context.coordinator.applyPendingCamera()
        }
    }

    static func dismantleUIView(_ map: FittableMapView, coordinator: Coordinator) {
        // The display link that walks the position dot outlives the coordinator otherwise.
        coordinator.stopDotSteps()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: FittableMapView?
        var parent: RouteMapView
        var appliedCameraToken = -1
        var pendingCamera: RouteMapView.Camera?

        private var toneOverlays: [ToneOverlay] = []
        private var appliedMode: MapMode?
        var appliedInterfaceStyle: UIUserInterfaceStyle?
        private var routeOverlays: [RouteColorOverlay] = []
        /// The renderers of the dotted jump overlays, so a zoom change can ask them to redraw.
        /// Rebuilt with the overlays; see `updateRoutes`.
        private var jumpRenderers: [JumpDotsRenderer] = []
        /// The visible width the dots were last redrawn at, and when — the map's own zoom proxy,
        /// since `MKMapView` has no public zoom scale. A redraw re-strokes the whole overlay, so
        /// it is throttled: the visible region changes on every pan frame too.
        private var jumpRedrawWidth: Double?
        private var jumpRedrawTime: CFTimeInterval = 0
        /// Routes already turned into overlays, so a reload that adds routes one at a
        /// time costs one polyline per arrival instead of rebuilding the whole set — with the
        /// ground each was built from, so an id that comes back standing for a different stretch
        /// is built again (see `updateRoutes`).
        private var polylines: [String: MKPolyline] = [:]
        private var polylineShapes: [String: PolylineShape] = [:]
        /// What a cached polyline was built from: two stretches of the same length can still be
        /// different ground, so both ends count as well as the number of fixes.
        private struct PolylineShape: Equatable {
            let count: Int
            let firstX: Double
            let firstY: Double
            let lastX: Double
            let lastY: Double

            init(_ line: MapRouteLine) {
                count = line.coordinates.count
                let first = MKMapPoint(line.coordinates[0])
                let last = MKMapPoint(line.coordinates[count - 1])
                firstX = first.x
                firstY = first.y
                lastX = last.x
                lastY = last.y
            }
        }
        private var signature = ""
        private var dotAnnotation: UserDotAnnotation?
        private var pinAnnotation: DestinationPinAnnotation?
        /// The dot's own animation — see `updateUserDot`.
        private lazy var dotProxy = DotProxy(coordinator: self)
        private var dotLink: CADisplayLink?
        private var dotStep: (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                              start: CFTimeInterval, duration: CFTimeInterval)?
        private var dotRendered: CLLocationCoordinate2D?
        private var dotTarget: CLLocationCoordinate2D?
        private var lastFixArrival: CFTimeInterval?

        /// The two recognizers the route editor borrows the map with: one finger erases, two
        /// fingers pan. Both are installed together and removed together (`updateEraser`), and
        /// while they are up the map's own pan is off.
        private var erasePan: UIPanGestureRecognizer?
        private var movePan: UIPanGestureRecognizer?
        /// The last point of the stroke in progress, so a step is reported as the segment the
        /// finger travelled rather than as a bare point — a fast drag must not leave ground
        /// between two reported points unerased.
        private var erasePrevious: MKMapPoint?
        /// The brush radius in the map's own units, measured once at the start of a stroke.
        private var eraseRadius: Double = 0
        /// The region a two-finger pan started from, so the map follows the fingers exactly
        /// instead of accumulating rounding into a region that is re-read every step.
        private var moveStartRegion: MKCoordinateRegion?

        /// What the cone points at: the compass first — that is what "facing" means, and it
        /// keeps working while the user stands still — and the direction of travel only when
        /// there is no compass reading at all (a phone whose magnetometer is disturbed, e.g.
        /// in a bus or a tunnel). `nil` — neither is known — takes the cone off the screen
        /// instead of leaving it pointing at something nobody measured.
        ///
        /// The heading arrives already turned onto the user's facing — `LocationProvider` takes
        /// the device's own rotation out of the compass reading, which is referenced to the top
        /// of the device — so nothing about the pose belongs here. A correction of our own,
        /// keyed on the *interface* orientation instead of the device's, turned the cone by 90°
        /// in every landscape pose (the Duo's inner display is laid out wide while the device
        /// itself stays upright, so the two disagree there).
        private var coneDirection: CLLocationDirection? {
            parent.userHeading ?? parent.userCourse
        }

        /// Points the cone after a fix, a heading or the camera moved.
        func applyDotDirection() {
            guard let map, let dotAnnotation,
                  let view = map.view(for: dotAnnotation) as? UserDotView else { return }
            view.apply(direction: coneDirection, cameraHeading: map.camera.heading)
        }

        init(_ parent: RouteMapView) { self.parent = parent }

        /// The tone arrives before any route, and MapKit draws overlays in the order
        /// they were added, so the routes land on top of it.
        func installToneOverlays() {
            guard let map else { return }
            toneOverlays = [ToneOverlay(fill: MapTone.desaturation, blend: .saturation, active: parent.mode.usesTone),
                            ToneOverlay(fill: MapTone.dim, blend: .normal, active: parent.mode.usesTone)]
            map.addOverlays(toneOverlays, level: .aboveLabels)
        }

        /// Swaps the map style. The tone pass is switched off inside its renderer rather
        /// than removed and re-added: MapKit draws the overlays of one level in the order
        /// they were added, so a tone pass re-added after the routes would grey those out.
        func updateMode() {
            guard let map, appliedMode != parent.mode else { return }
            appliedMode = parent.mode
            // MapKit has no animated form of this; the style swaps in one frame.
            map.preferredConfiguration = parent.mode.configuration()
            let wanted = parent.mode.usesTone
            guard toneOverlays.contains(where: { $0.active != wanted }) else { return }
            for tone in toneOverlays {
                tone.active = wanted
                map.renderer(for: tone)?.setNeedsDisplay()
            }
        }

        /// Swaps the map's light/dark style. MapKit redraws its tiles and labels for it, so the
        /// map follows the system's setting — or the one the user pinned — without a reload.
        ///
        /// Swaps the map's light/dark style. MapKit redraws its tiles and labels for it, so the
        /// map follows the system's setting — or the one the user pinned — without a reload.
        ///
        /// MapKit has no animated form of this: the tiles and labels swap in one frame. Nothing
        /// can fade them either — the tiles are drawn by a Metal layer of the map's own, so
        /// `UIView.transition` has nothing to snapshot and swaps in one frame as well
        /// (measured). The screen answers with a wash instead — see `MapTabView.appearanceWash`.
        func updateAppearance() {
            guard let map, appliedInterfaceStyle != parent.interfaceStyle else { return }
            appliedInterfaceStyle = parent.interfaceStyle
            map.overrideUserInterfaceStyle = parent.interfaceStyle
            map.backgroundColor = .systemBackground
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
            // A single tap, for picking a route. It is not the pan/pinch recognizers' business:
            // it neither moves the camera nor counts as user interaction, it only reports which
            // route — if any — the tap landed on.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            map.addGestureRecognizer(tap)
            // A long press, for dropping the explorer's destination pin — Maps' own gesture
            // for the same thing. It reports where it landed, once, as it begins.
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            press.cancelsTouchesInView = false
            press.minimumPressDuration = 0.4
            press.delegate = self
            map.addGestureRecognizer(press)
        }

        /// Puts the eraser on the map while the editor is up, and takes it off again.
        ///
        /// With a brush, MapKit's own pan — which cannot be told to leave a single finger alone —
        /// is parked (`isScrollEnabled`) and two recognizers of our own take over: a one-finger
        /// drag that erases, and a two-finger drag that pans the map by moving its region. A pinch
        /// and a rotation are untouched, so the map still zooms and turns the way it does
        /// everywhere else.
        func updateEraser() {
            guard let map else { return }
            let wanted = parent.eraserRadius != nil
            guard wanted != (erasePan != nil) else { return }
            if wanted {
                let erase = UIPanGestureRecognizer(target: self, action: #selector(handleErase(_:)))
                erase.maximumNumberOfTouches = 1
                erase.cancelsTouchesInView = false
                erase.delegate = self
                map.addGestureRecognizer(erase)
                erasePan = erase

                let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
                move.minimumNumberOfTouches = 2
                move.cancelsTouchesInView = false
                move.delegate = self
                map.addGestureRecognizer(move)
                movePan = move

                map.isScrollEnabled = false
            } else {
                if let erasePan { map.removeGestureRecognizer(erasePan) }
                if let movePan { map.removeGestureRecognizer(movePan) }
                erasePan = nil
                movePan = nil
                map.isScrollEnabled = true
            }
        }

        /// One finger, erasing: every step the finger takes is handed on with the brush's own
        /// radius converted into the map's units right there, so a fixed brush covers the ground
        /// the finger covers whatever the zoom.
        @objc private func handleErase(_ recognizer: UIPanGestureRecognizer) {
            guard let map, let brush = parent.eraserRadius, map.bounds.width > 1 else { return }
            let point = recognizer.location(in: map)
            switch recognizer.state {
            case .began:
                parent.onEraseCursor?(point)
                eraseRadius = mapPointsPerPoint(at: point, in: map) * Double(brush)
                let current = MKMapPoint(map.convert(point, toCoordinateFrom: map))
                parent.onErase?(nil, current, eraseRadius)
                erasePrevious = current
            case .changed:
                let current = MKMapPoint(map.convert(point, toCoordinateFrom: map))
                parent.onErase?(erasePrevious, current, eraseRadius)
                erasePrevious = current
                parent.onEraseCursor?(point)
            case .ended, .cancelled, .failed:
                parent.onEraseCursor?(nil)
                erasePrevious = nil
            default:
                break
            }
        }

        /// Two fingers, panning — MapKit's own pan is parked while a brush is up.
        @objc private func handleMove(_ recognizer: UIPanGestureRecognizer) {
            guard let map, recognizer.numberOfTouches >= 2 else { return }
            switch recognizer.state {
            case .began:
                moveStartRegion = map.region
            case .changed:
                guard let start = moveStartRegion else { return }
                let translation = recognizer.translation(in: map)
                let perPointX = start.span.longitudeDelta / Double(max(map.bounds.width, 1))
                let perPointY = start.span.latitudeDelta / Double(max(map.bounds.height, 1))
                map.setRegion(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: start.center.latitude + Double(translation.y) * perPointY,
                        longitude: start.center.longitude - Double(translation.x) * perPointX),
                    span: start.span),
                              animated: false)
            case .ended, .cancelled, .failed:
                moveStartRegion = nil
            default:
                break
            }
        }

        /// How many map points one point of the screen is worth where the finger is — the same
        /// measurement the tap hit-test takes for its own radius.
        private func mapPointsPerPoint(at point: CGPoint, in map: MKMapView) -> Double {
            let a = MKMapPoint(map.convert(point, toCoordinateFrom: map))
            let b = MKMapPoint(map.convert(CGPoint(x: point.x + 1, y: point.y), toCoordinateFrom: map))
            return abs(b.x - a.x)
        }

#if DEBUG
        /// `WM_ERASE` — see `DebugLaunch.eraseStroke`. The simulator offers no way to drag a finger
        /// from the command line, so the stroke is run through the very path the eraser recognizer
        /// uses. The brush is left standing where the stroke ended, so a screenshot shows the brush
        /// as well as what it took out.
        func runEraseProbeIfRequested() {
            guard let stroke = DebugLaunch.eraseStroke, stroke.count > 1,
                  parent.eraserRadius != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + DebugLaunch.eraseDelay) { [weak self] in
                guard let self, let map = self.map, let brush = self.parent.eraserRadius else { return }
                var previous: MKMapPoint?
                for point in stroke {
                    let current = MKMapPoint(map.convert(point, toCoordinateFrom: map))
                    self.parent.onEraseCursor?(point)
                    self.parent.onErase?(previous, current,
                                         self.mapPointsPerPoint(at: point, in: map) * Double(brush))
                    previous = current
                }
            }
        }
#endif

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let map, recognizer.state == .began else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            parent.onLongPress?(coordinate)
        }

        @objc private func handleGesture(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .changed, .ended: parent.onUserInteraction?()
            default: break
            }
        }

        /// Reports the route under the finger, or `nil` for a tap on the map itself.
        ///
        /// The routes are MapKit overlays, which have no tap target, so the tap is resolved
        /// against the geometry: the tap's map point, and every route's segments, both in the
        /// same projected space. One pass per tap — never per frame — so the cost of walking
        /// every point is not on the render path.
        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map, recognizer.state == .ended else { return }
            reportRouteTap(at: recognizer.location(in: map))
        }

        /// Resolves a tap at a point in the map view and reports the route under it, or `nil`
        /// for a tap on the map itself.
        func reportRouteTap(at point: CGPoint) {
            guard let map, map.bounds.width > 1 else { return }
            // A tap on the pin is the pin's own business — it opens the info bubble — and not a
            // route pick.
            if let pinAnnotation, let pinView = map.view(for: pinAnnotation),
               pinView.frame.contains(point) { return }
            let tapped = MKMapPoint(map.convert(point, toCoordinateFrom: map))
            // The hit radius in the map's own units, taken from the map itself rather than
            // guessed: the same 24 pt to the right of the tap, measured in map points, is the
            // scale the routes are drawn at right here.
            let beside = MKMapPoint(map.convert(CGPoint(x: point.x + Self.tapRadius, y: point.y),
                                                toCoordinateFrom: map))
            let radius = abs(beside.x - tapped.x)
            guard radius > 0 else { return }
            // A planned route comes first: it is drawn on top of the workout routes, so a tap
            // that lands on one is meant for it.
            if let index = plannedIndex(near: tapped, within: radius) {
                parent.onPlannedTap?(index)
                return
            }
            parent.onRouteTap?(routeID(near: tapped, within: radius))
        }

        /// The planned route whose stroke passes within `threshold` map points of `point`, or
        /// `nil` when the tap missed every one of them.
        private func plannedIndex(near point: MKMapPoint, within threshold: Double) -> Int? {
            var best: (index: Int, distance: Double)?
            let limit = threshold * threshold
            for line in parent.planned where line.coordinates.count > 1 {
                guard let index = Coordinator.plannedIndex(of: line.id) else { continue }
                var nearest = Double.greatestFiniteMagnitude
                var previous: MKMapPoint?
                for coordinate in line.coordinates {
                    let current = MKMapPoint(coordinate)
                    if let previous {
                        nearest = min(nearest, Geo.pointToSegmentSquared(point, previous, current))
                    }
                    previous = current
                }
                guard nearest <= limit else { continue }
                if best == nil || nearest < best!.distance { best = (index, nearest) }
            }
            return best?.index
        }

        /// `plan-2` and `plan-2-casing` are both route 2.
        private static func plannedIndex(of id: String) -> Int? {
            guard id.hasPrefix("plan-") else { return nil }
            return Int(id.dropFirst(5).prefix { $0 != "-" })
        }

        /// The id of the nearest route whose stroke passes within `threshold` map points of
        /// `point`, or `nil` when the tap missed every one of them.
        private func routeID(near point: MKMapPoint, within threshold: Double) -> String? {
            var best: (id: String, distance: Double)?
            let limit = threshold * threshold
            for line in parent.routes where line.coordinates.count > 1 {
                var nearest = Double.greatestFiniteMagnitude
                var previous: MKMapPoint?
                for coordinate in line.coordinates {
                    let current = MKMapPoint(coordinate)
                    if let previous {
                        nearest = min(nearest, Geo.pointToSegmentSquared(point, previous, current))
                    }
                    previous = current
                }
                guard nearest <= limit else { continue }
                if best == nil || nearest < best!.distance { best = (Coordinator.baseRouteID(line.id), nearest) }
            }
            return best?.id
        }

        /// `abc#jump1` is a jump leg of route `abc` and `abc#2` its second walked stretch, so a
        /// tap on either is a tap on the workout `abc`.
        static func baseRouteID(_ id: String) -> String {
            guard let cut = id.firstIndex(of: "#") else { return id }
            return String(id[id.startIndex..<cut])
        }

        /// How close to a route a tap counts as landing on it. The routes are ~3 pt wide; 24 pt
        /// is a comfortable finger target around them.
        private static let tapRadius: CGFloat = 24

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
        ///
        /// The workout routes come first and the explorer's planned ones after them: MapKit
        /// draws the overlays of one level in the order they were added, so a planned route
        /// always lands on top of the routes underneath it instead of disappearing into them.
        func updateRoutes() {
            guard let map else { return }
            var next = ""
            for line in parent.routes {
                next += line.id
                next += "|\(line.coordinates.count)|\(line.color.hashValue)|\(line.dash?.description ?? "-");"
            }
            next += "/"
            for line in parent.planned {
                next += line.id
                next += "|\(line.coordinates.count)|\(line.color.hashValue)|\(line.width)|\(line.dash?.description ?? "-");"
            }
            guard next != signature else { return }
            signature = next

            let lines = parent.routes + parent.planned
            var wanted: Set<String> = []
            for line in lines where line.coordinates.count > 1 {
                wanted.insert(line.id)
                let shape = PolylineShape(line)
                // An id outlives the stretch it stands for: a jump rule moved and the route was
                // cut another way, and the id (`…-0`, `…-distance1`) came back as different
                // ground. One that kept its shape is left as it is — that is what makes a reload
                // that arrives in batches cost one polyline per arrival.
                guard polylines[line.id] != nil, polylineShapes[line.id] == shape else {
                    polylines[line.id] = MKPolyline(coordinates: line.coordinates,
                                                    count: line.coordinates.count)
                    polylineShapes[line.id] = shape
                    continue
                }
            }
            polylines = polylines.filter { wanted.contains($0.key) }
            polylineShapes = polylineShapes.filter { wanted.contains($0.key) }

            var grouped: [(color: UIColor, width: CGFloat, dash: [CGFloat]?, polylines: [MKPolyline])] = []
            for line in lines {
                guard let polyline = polylines[line.id] else { continue }
                if let index = grouped.firstIndex(where: { $0.color == line.color && $0.width == line.width
                                                           && $0.dash == line.dash }) {
                    grouped[index].polylines.append(polyline)
                } else {
                    grouped.append((line.color, line.width, line.dash, [polyline]))
                }
            }

            map.removeOverlays(routeOverlays)
            jumpRenderers = []
            routeOverlays = grouped.map {
                RouteColorOverlay(color: $0.color, width: $0.width, dash: $0.dash, polylines: $0.polylines)
            }
            map.addOverlays(routeOverlays, level: .aboveLabels)
        }

        /// Adds, moves or removes the explorer's destination pin. One at a time: a new
        /// coordinate moves the pin it already has instead of adding a second one.
        ///
        /// The address arrives after the pin does — it is geocoded — so the bubble's text is
        /// written here and an open bubble is refreshed rather than left stale.
        func updatePin() {
            guard let map else { return }
            guard let coordinate = parent.pin else {
                if let pinAnnotation {
                    map.removeAnnotation(pinAnnotation)
                    self.pinAnnotation = nil
                }
                return
            }
            if let pinAnnotation {
                let moved = !Coordinator.matches(pinAnnotation.coordinate, coordinate)
                pinAnnotation.coordinate = coordinate
                if moved || pinAnnotation.title != parent.pinTitle {
                    pinAnnotation.title = parent.pinTitle
                    // The callout is laid out when it is shown and does not watch the annotation,
                    // so an open one is redrawn when the place name finally arrives.
                    if !moved { refreshCallout(of: pinAnnotation, in: map) }
                }
            } else {
                let annotation = DestinationPinAnnotation(coordinate: coordinate,
                                                          title: parent.pinTitle)
                pinAnnotation = annotation
                map.addAnnotation(annotation)
            }
            updatePinAccessory(in: map)
#if DEBUG
            runPinProbe()
#endif
        }

        /// Keeps the pin's bubble saying where it is and how far away that is — the bubble is the
        /// one place the user is standing when they ask, and the distance changes as they walk.
        private func updatePinAccessory(in map: MKMapView) {
            guard let pinAnnotation,
                  let view = map.view(for: pinAnnotation) as? DestinationPinView else { return }
            view.apply(address: parent.pinSubtitle,
                       distance: parent.userLocation.map {
                           CoverageIndex.meters(from: $0, to: pinAnnotation.coordinate)
                       })
        }

#if DEBUG
        /// `WM_SELECT_PIN` / `WM_PIN_DELETE` — see `DebugLaunch`. The simulator has no way to
        /// tap the map from the command line, so the bubble is opened and the bin fired from
        /// here — the bin through the very delegate method MapKit calls for it.
        private func runPinProbe() {
            guard let map, let pinAnnotation else { return }
            guard DebugLaunch.selectPin || DebugLaunch.pinDelete else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak map] in
                guard let self, let map, let view = map.view(for: pinAnnotation) else { return }
                if DebugLaunch.selectPin { map.selectAnnotation(pinAnnotation, animated: true) }
                guard DebugLaunch.pinDelete else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.mapView(map, annotationView: view,
                                 calloutAccessoryControlTapped: UIButton())
                }
            }
        }
#endif

        /// Redraws an open bubble after its text changed: MapKit lays a callout out when it is
        /// shown and does not watch the annotation for changes.
        private func refreshCallout(of annotation: MKAnnotation, in map: MKMapView) {
            guard let view = map.view(for: annotation), view.isSelected else { return }
            map.deselectAnnotation(annotation, animated: false)
            map.selectAnnotation(annotation, animated: false)
        }

        /// Moves the dot onto the newest fix.
        ///
        /// The dot is an annotation of our own, so MapKit does not animate it the way it
        /// animates its built-in user location — every fix would teleport it. And there is no
        /// faster stream to wait for: a fix arrives roughly once a second, which is what the
        /// receiver has to give (`LocationProvider` asks it for the most there is; a phone's
        /// GPS has no 60 Hz to offer). So the dot is walked by hand, at the display's own
        /// refresh rate: each fix starts a step from where the dot currently is to that fix,
        /// over the interval the previous fix took — it runs one fix behind reality and lands
        /// just as the next one arrives. The step is a display link and stops the moment the
        /// dot has caught up.
        func updateUserDot() {
            guard let map else { return }
            guard let location = parent.userLocation else {
                stopDotSteps()
                if let dotAnnotation {
                    map.removeAnnotation(dotAnnotation)
                    self.dotAnnotation = nil
                }
                dotRendered = nil
                dotTarget = nil
                lastFixArrival = nil
                return
            }
            guard let dotAnnotation else {
                let annotation = UserDotAnnotation(coordinate: location)
                self.dotAnnotation = annotation
                dotRendered = location
                dotTarget = location
                map.addAnnotation(annotation)
                return
            }
            (map.view(for: dotAnnotation) as? UserDotView)?.apply(color: parent.userDotColor)
            stepDot(towards: location, annotation: dotAnnotation)
            applyDotDirection()
        }

        private func stepDot(towards target: CLLocationCoordinate2D, annotation: UserDotAnnotation) {
            guard !Coordinator.matches(dotTarget, target) else { return }
            let now = CACurrentMediaTime()
            let gap = lastFixArrival.map { now - $0 } ?? .infinity
            lastFixArrival = now
            dotTarget = target
            // A gap far longer than a fix interval is not a stream of positions — the screen
            // was away and the dot may have a city to cross. It jumps instead of sliding.
            guard gap < 3, let from = dotRendered, !Coordinator.matches(from, target) else {
                stopDotSteps()
                dotRendered = target
                annotation.coordinate = target
                return
            }
            dotStep = (from, target, now, min(max(gap, 0.2), 2))
            startDotLink()
        }

        private func startDotLink() {
            guard dotLink == nil else { return }
            let link = CADisplayLink(target: dotProxy, selector: #selector(DotProxy.step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            dotLink = link
        }

        func stopDotSteps() {
            dotLink?.invalidate()
            dotLink = nil
            dotStep = nil
        }

        /// One frame of the step: the dot sits at `from` + progress · (to − from).
        private func stepDot(_ link: CADisplayLink) {
            guard let step = dotStep, let annotation = dotAnnotation else { stopDotSteps(); return }
            let elapsed = CACurrentMediaTime() - step.start
            let progress = step.duration > 0 ? min(1, elapsed / step.duration) : 1
            let coordinate = Coordinator.interpolate(step.from, step.to, progress)
            dotRendered = coordinate
            annotation.coordinate = coordinate
            if progress >= 1 { stopDotSteps() }
        }

        /// `CLLocationCoordinate2D` is not `Equatable` here, and one fix is repeated by every
        /// unrelated redraw of the screen.
        private static func matches(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D) -> Bool {
            guard let lhs else { return false }
            return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        }

        /// Linear, the short way round the globe: a fix pair never spans more than a few
        /// hundred metres, but a longitude that wraps must not send the dot the long way.
        private static func interpolate(_ from: CLLocationCoordinate2D,
                                        _ to: CLLocationCoordinate2D,
                                        _ t: Double) -> CLLocationCoordinate2D {
            let delta = ((to.longitude - from.longitude + 540).truncatingRemainder(dividingBy: 360)) - 180
            return CLLocationCoordinate2D(latitude: from.latitude + (to.latitude - from.latitude) * t,
                                          longitude: from.longitude + delta * t)
        }

        /// `CADisplayLink` retains its target. This holds the coordinator weakly, so a screen
        /// that goes away is not kept alive — and kept stepping — by a scheduled link.
        final class DotProxy: NSObject {
            weak var coordinator: Coordinator?

            init(coordinator: Coordinator) { self.coordinator = coordinator }

            @objc func step(_ link: CADisplayLink) { coordinator?.stepDot(link) }
        }

        // MARK: delegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is DestinationPinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: DestinationPinView.reuseIdentifier,
                                                                 for: annotation)
                // Set here as well as in `updatePinAccessory`, so a bubble opened before the next
                // update already has its lines rather than empty ones.
                if let pin = view as? DestinationPinView {
                    pin.apply(address: parent.pinSubtitle,
                              distance: parent.userLocation.map {
                                  CoverageIndex.meters(from: $0, to: annotation.coordinate)
                              })
                }
                return view
            }
            guard annotation is UserDotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: UserDotView.reuseIdentifier,
                                                             for: annotation)
            if let dot = view as? UserDotView {
                dot.apply(color: parent.userDotColor)
                dot.apply(direction: coneDirection, cameraHeading: mapView.camera.heading)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tone = overlay as? ToneOverlay { return ToneOverlayRenderer(tone: tone) }
            guard let group = overlay as? RouteColorOverlay else { return MKOverlayRenderer(overlay: overlay) }
            if group.dash != nil {
                // A jump: drawn as dots by hand — MapKit's dashed stroke does not hold its size
                // against the map's zoom (see `JumpDotsRenderer`) — and kept in the list so a
                // zoom change can ask for a redraw.
                let renderer = JumpDotsRenderer(overlay: group)
                jumpRenderers = jumpRenderers.filter { $0.overlay !== group }
                jumpRenderers.append(renderer)
                return renderer
            }
            let renderer = MKMultiPolylineRenderer(multiPolyline: group)
            renderer.strokeColor = group.color
            renderer.lineWidth = group.width
            renderer.lineJoin = .round
            if let dash = group.dash {
                // A round cap on a zero-length dash is a circle — the jump's dot — and the
                // pattern's second length is what keeps two of them apart.
                renderer.lineCap = .round
                renderer.lineDashPattern = dash.map { NSNumber(value: $0) }
            } else {
                renderer.lineCap = .round
            }
            return renderer
        }

        /// The bin in the pin's info bubble.
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard view.annotation is DestinationPinAnnotation else { return }
            mapView.deselectAnnotation(view.annotation, animated: true)
            parent.onPinDelete?()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange?(mapView.visibleMapRect)
        }

        /// Fires continuously while the map is turned: the cone is drawn in the screen's frame,
        /// so it has to follow the camera's heading or it would point at the wrong place.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            applyDotDirection()
            redrawJumpDotsIfZoomChanged(mapView)
        }

        /// Keeps a jump's dots at the size this zoom calls for.
        ///
        /// A dashed stroke is rasterised per tile level, so between two levels MapKit scales the
        /// tile it already drew and the dots drift in size with the map. Asking the renderers to
        /// redraw when the zoom has actually moved pulls them back — and both halves of that are
        /// throttled, because a redraw re-strokes every dot on screen and the visible region
        /// changes on every pan frame as well: only the tiles on screen are asked for again, and
        /// only once the zoom has moved the dots by more than a fraction of a dot.
        private func redrawJumpDotsIfZoomChanged(_ map: MKMapView) {
            guard !jumpRenderers.isEmpty else { return }
            let rect = map.visibleMapRect
            let width = rect.width
            let now = CACurrentMediaTime()
            if let previous = jumpRedrawWidth {
                // What the zoom can have moved a dot by is the ratio of the two visible widths.
                // The dots are a handful of points across, so a tenth of one is not worth the
                // strokes: the redraw is left for a real move, not for every pinch frame.
                let moved = abs(width - previous) / max(width, previous)
                guard moved > 0.15 else { return }
            }
            guard now - jumpRedrawTime >= 0.15 else { return }
            jumpRedrawWidth = width
            jumpRedrawTime = now
            for renderer in jumpRenderers { renderer.setNeedsDisplay(rect) }
        }
    }
}

extension RouteMapView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
