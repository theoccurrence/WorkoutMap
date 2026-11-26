import UIKit
import MapKit
import CoreLocation

struct RouteLine {
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
    /// The dash pattern, in points, for a line that stands for ground the user did not cover — a
    /// GPS jump. `nil` is a solid line. The dashes are stroked with square ends so one does not
    /// grow into the gap beside it.
    var dash: [CGFloat]? = nil
    /// Overrides the shared `lineWidth`, for a jump drawn thinner than the route it interrupts.
    var width: CGFloat? = nil
}

/// Renders MapKit snapshots with the app's dark muted style and optional route overlays.
final class MapImageRenderer {
    static let shared = MapImageRenderer()

    /// How tall a band is cropped off a snapshot's bottom edge to take MapKit's own *Maps*
    /// attribution with it. The wordmark is drawn ~20 pt up from that edge and is ~15 pt tall, so
    /// the 14 pt band the app used reached none of it: every snapshot it drew — the list thumbnails
    /// and the share cards alike — carried MapKit's attribution, and a card, which draws the *Maps*
    /// line for itself, carried both.
    static let attributionBand: CGFloat = 40

    /// The rect grown about its centre to the given width/height ratio, so a snapshot taken at that
    /// ratio holds this rect and nothing else it does not have to.
    static func fitted(_ rect: MKMapRect, aspect: CGFloat) -> MKMapRect {
        guard aspect > 0, rect.size.width > 0, rect.size.height > 0 else { return rect }
        if rect.size.width / rect.size.height < aspect {
            let width = rect.size.height * aspect
            return MKMapRect(x: rect.midX - width / 2, y: rect.minY,
                             width: width, height: rect.size.height)
        }
        let height = rect.size.width / aspect
        return MKMapRect(x: rect.minX, y: rect.midY - height / 2,
                         width: rect.size.width, height: height)
    }

    private let cache = NSCache<NSString, UIImage>()
    private static let ciContext = CIContext(options: nil)

    /// Applies a linear tone curve directly on sRGB pixels, keeping `chroma` of each
    /// pixel's own colour and the rest of its luma: 0 is the flat grey the live map's own tone pass
    /// leaves behind (measured over a legacy map: a mean chroma of 3 of 255, against 21 for the
    /// untouched colour — so a card that keeps half of it comes out seven times as colourful as the
    /// map it was drawn from), 1 keeps the colour. Doing this by hand avoids Core Image's linear
    /// working space, which makes brightness/contrast behave unpredictably for the app's flat look.
    private func toneMapped(_ image: UIImage,
                            chroma: CGFloat,
                            scale: CGFloat,
                            offset: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return image }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let red = CGFloat(ptr[index])
            let green = CGFloat(ptr[index + 1])
            let blue = CGFloat(ptr[index + 2])
            let luma = 0.299 * red + 0.587 * green + 0.114 * blue
            let gray = (1 - chroma) * luma
            ptr[index] = UInt8(max(0, min(255, (chroma * red + gray) * scale + offset)))
            ptr[index + 1] = UInt8(max(0, min(255, (chroma * green + gray) * scale + offset)))
            ptr[index + 2] = UInt8(max(0, min(255, (chroma * blue + gray) * scale + offset)))
        }
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    /// A **live** map view's own rendering, as an image.
    ///
    /// This is the only way to get the app's routes on a tilted map *and* MapKit's 3D around them. A
    /// snapshotter cannot draw the routes at all — Apple's own advice is to draw an overlay by hand, so
    /// the app does — but a route drawn by hand over a tilted snapshot has no depth: it lies across the
    /// buildings it should pass behind, which is not what the map the user is looking at shows. The
    /// screen's own map view has all of it already: the routes are `MKOverlay`s inside MapKit's own
    /// render pass, occluded by the extruded blocks exactly as on screen, the tone pass and all.
    /// `drawHierarchy(in:afterScreenUpdates:)` is what takes that rendering off the view — measured on
    /// iOS: the tiles, the extruded buildings, the labels and the routes, in the camera's own
    /// perspective, pixel for pixel the map on screen. (`layer.render(in:)`, the other candidate, comes
    /// back an empty rectangle for a map, and worse, takes the process down with it.)
    ///
    /// `nil` when there is nothing to draw — the method's own `false`, which is what a view that has
    /// never been on screen reports — so a caller can fall back to a snapshot.
    static func liveImage(of view: UIView, scale: CGFloat) -> UIImage? {
        guard view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            drawn = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        return drawn ? image : nil
    }

    /// One snapshot per map style, so a thumbnail shows the same map the list is of.
    private func snapshot(mapRect: MKMapRect,
                          size: CGSize,
                          scale: CGFloat,
                          mode: MapMode,
                          interfaceStyle: UIUserInterfaceStyle) async -> MKMapSnapshotter.Snapshot? {
        guard size.width > 1, size.height > 1 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.mapRect = mapRect
        options.size = size
        options.scale = scale
        options.preferredConfiguration = mode.configuration(satelliteLabels: MapMode.satelliteLabels)
        options.traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle)
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)
        return try? await snapshotter.start()
    }

    /// Map + routes rendered into one image — the **thumbnails** the workout list is drawn of. (A
    /// share card's map is not made here: it is the map view the card was showing, drawn off the view
    /// itself, which is the only way the routes and the 3D buildings come out with the depth between
    /// them — see `liveImage(of:scale:)`.)
    ///
    /// The tone curve is applied for the modes that carry the app's grey (`MapMode.usesTone`) and skipped
    /// for the rest, which are the map as MapKit draws it.
    func image(mapRect: MKMapRect,
               size: CGSize,
               scale: CGFloat,
               routes: [RouteLine],
               mode: MapMode = .legacy,
               interfaceStyle: UIUserInterfaceStyle = .dark,
               lineWidth: CGFloat = 7,
               toneChroma: CGFloat = 0,
               toneScale: CGFloat = 1,
               toneOffset: CGFloat = 0,
               attributionBand: CGFloat = MapImageRenderer.attributionBand) async -> UIImage? {
        // MapKit draws its "Maps" attribution into the snapshot's bottom edge. The original app
        // shows no attribution in the card thumbnails, so the snapshot is taken a band taller and
        // that band is cropped off — the canvas keeps the snapshot's **top**.
        //
        // The region is grown to the canvas' own ratio first and then extended **downwards** by the
        // band, so that the canvas holds exactly the rect that was asked for: a snapshot taken
        // taller and cropped would otherwise show a region of its own, shifted and zoomed by the
        // band — 40 pt of a 90 pt thumbnail is nearly half of it.
        let canvasAspect = size.width / max(1, size.height)
        let snapshotAspect = size.width / max(1, size.height + attributionBand)
        let visible = MapImageRenderer.fitted(mapRect, aspect: canvasAspect)
        let snapshotRect = MKMapRect(x: visible.minX,
                                     y: visible.minY,
                                     width: visible.width,
                                     height: visible.width / snapshotAspect)
        let snapshotSize = CGSize(width: size.width, height: size.height + attributionBand)
        guard let snapshot = await snapshot(mapRect: snapshotRect, size: snapshotSize, scale: scale,
                                            mode: mode, interfaceStyle: interfaceStyle) else { return nil }
        let base = mode.usesTone
            ? toneMapped(snapshot.image, chroma: toneChroma, scale: toneScale, offset: toneOffset)
            : snapshot.image
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // Drawn at the canvas' own origin, so the canvas — which is `attributionBand` shorter —
            // keeps the snapshot's **top** and drops that band off its **bottom**, where MapKit put
            // its attribution. Shifting it up by the band instead (which is what this did) kept the
            // bottom and cut the top: the attribution stayed in every snapshot the app drew, and the
            // *Maps* line a share card draws for itself was left sitting over it.
            base.draw(in: CGRect(x: 0, y: 0, width: size.width, height: snapshotSize.height))
            let cg = context.cgContext
            cg.setLineJoin(.round)
            for route in routes where route.coordinates.count > 1 {
                cg.setStrokeColor(route.color.cgColor)
                cg.setLineWidth(route.width ?? lineWidth)
                if let dash = route.dash {
                    // A round cap on a zero-length dash is the jump's dot — see `RouteJump`.
                    cg.setLineCap(.round)
                    cg.setLineDash(phase: 0, lengths: dash)
                } else {
                    cg.setLineCap(.round)
                    cg.setLineDash(phase: 0, lengths: [])
                }
                let path = CGMutablePath()
                for (index, coordinate) in route.coordinates.enumerated() {
                    // The snapshot's own space, which is the canvas' now that it is drawn at the
                    // origin — the routes move with the map they are drawn over.
                    let point = snapshot.point(for: coordinate)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                cg.addPath(path)
                cg.strokePath()
            }
        }
    }

    /// The original app frames a card thumbnail as the route's bounding box plus a
    /// fixed geographic margin, extended to the card's aspect ratio.
    static func thumbnailMapRect(route: [CLLocationCoordinate2D],
                                 aspect: CGFloat,
                                 marginMeters: Double = 100) -> MKMapRect? {
        guard let bbox = RouteGeometry.union([route]) else { return nil }
        let coordinate = MKMapPoint(x: bbox.midX, y: bbox.midY).coordinate
        let margin = MKMapPointsPerMeterAtLatitude(coordinate.latitude) * marginMeters
        var rect = bbox.insetBy(dx: -margin, dy: -margin)
        if rect.height < 1 { rect = MKMapRect(x: rect.midX, y: rect.midY, width: max(rect.width, margin), height: margin) }
        if rect.width / rect.height < aspect {
            let width = rect.height * aspect
            rect = MKMapRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        } else {
            let height = rect.width / aspect
            rect = MKMapRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        return rect
    }

    /// Card thumbnail: the workout route over a heavily dimmed map.
    func thumbnail(for id: UUID,
                   route: WorkoutRoute,
                   color: UIColor,
                   rules: JumpRules,
                   tones: JumpTones,
                   edits: RouteEdits = .empty,
                   size: CGSize,
                   scale: CGFloat) async -> UIImage? {
        // The rules, the mode's colour, the tones the jump legs are drawn in and the edits the user
        // made are part of the key: the same workout is drawn differently once any of them changes,
        // and a cached image of the other look must not come back.
        let key = "\(id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(Int(scale * 100))-\(rules.key)-\(tones.key)-\(color.hexRGB)-\(edits.key)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let aspect = size.height > 1 ? size.width / size.height : 4
        // What is left after the erasure frames it, so an erased stretch does not push the route
        // into a corner of the card. A flagged leg is drawn, so it counts here as well.
        let visible = route.visible(edits)
        let rect = MapImageRenderer.thumbnailMapRect(route: visible, aspect: aspect)
            ?? RouteGeometry.fitted(RouteGeometry.mapRect(for: visible.first ?? CLLocationCoordinate2D()))
        // A leg's dots are measured against the 2.4 pt the route itself is drawn at in a
        // thumbnail, so they follow that weight instead of carrying one of their own.
        let thumbnailRouteWidth: CGFloat = 2.4
        // A thumbnail is a preview of the map, so a flagged leg is drawn as part of the route: the
        // flag is this app's own business and the card's job is to look like the workout.
        let drawing = route.drawing(rules, edits: edits)
        var lines = drawing.walked.map { RouteLine(coordinates: $0, color: color) }
        for leg in drawing.legs {
            switch rules.style(for: leg.kind) {
            case .hidden:
                continue
            case .dotted:
                lines.append(RouteLine(coordinates: leg.coordinates,
                                       color: tones.uiColor(for: leg.kind),
                                       dash: RouteJump.dotDash(routeWidth: thumbnailRouteWidth),
                                       width: RouteJump.dotDiameter(routeWidth: thumbnailRouteWidth)))
            case .solid:
                lines.append(RouteLine(coordinates: leg.coordinates,
                                       color: tones.uiColor(for: leg.kind)))
            }
        }
        let image = await image(mapRect: rect, size: size, scale: scale,
                                routes: lines,
                                lineWidth: thumbnailRouteWidth,
                                toneChroma: 0,
                                toneScale: 0.29,
                                toneOffset: 16)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
