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

    private let cache = NSCache<NSString, UIImage>()
    private static let ciContext = CIContext(options: nil)

    /// Applies a linear tone curve directly on sRGB pixels, keeping `chroma` of each
    /// pixel's own colour and the rest of its luma: 0 is the flat grey of the cards, 0.5 is
    /// the grey the live map's tone pass leaves behind, 1 keeps the colour. Doing this by hand avoids Core Image's linear working space, which makes
    /// brightness/contrast behave unpredictably for the app's flat look.
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

    /// One snapshot per map style, so an exported card shows the same map the user was
    /// looking at.
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
        options.preferredConfiguration = mode.configuration()
        options.traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle)
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)
        return try? await snapshotter.start()
    }

    /// Map + routes rendered into one image. The tone curve is applied for the modes that
    /// carry the app's grey (`MapMode.usesTone`) and skipped for the rest, which are the map
    /// as MapKit draws it.
    func image(mapRect: MKMapRect,
               size: CGSize,
               scale: CGFloat,
               routes: [RouteLine],
               mode: MapMode = .legacy,
               interfaceStyle: UIUserInterfaceStyle = .dark,
               lineWidth: CGFloat = 7,
               toneChroma: CGFloat = 0,
               toneScale: CGFloat = 1,
               toneOffset: CGFloat = 0) async -> UIImage? {
        // MapKit draws its "Maps" attribution into the snapshot's bottom edge.
        // The original app shows no attribution in the card thumbnails, so the
        // snapshot is taken a little taller and that band is cropped off.
        let attributionBand: CGFloat = 14
        let snapshotSize = CGSize(width: size.width, height: size.height + attributionBand)
        guard let snapshot = await snapshot(mapRect: mapRect, size: snapshotSize, scale: scale,
                                            mode: mode, interfaceStyle: interfaceStyle) else { return nil }
        let base = mode.usesTone
            ? toneMapped(snapshot.image, chroma: toneChroma, scale: toneScale, offset: toneOffset)
            : snapshot.image
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            base.draw(in: CGRect(x: 0, y: -attributionBand, width: size.width, height: snapshotSize.height))
            let cg = context.cgContext
            cg.setLineJoin(.round)
            for route in routes where route.coordinates.count > 1 {
                cg.setStrokeColor(route.color.cgColor)
                cg.setLineWidth(route.width ?? lineWidth)
                if let dash = route.dash {
                    cg.setLineCap(.butt)
                    cg.setLineDash(phase: 0, lengths: dash)
                } else {
                    cg.setLineCap(.round)
                    cg.setLineDash(phase: 0, lengths: [])
                }
                let path = CGMutablePath()
                for (index, coordinate) in route.coordinates.enumerated() {
                    let raw = snapshot.point(for: coordinate)
                    let point = CGPoint(x: raw.x, y: raw.y - attributionBand)
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
                   style: RouteJumpStyle,
                   size: CGSize,
                   scale: CGFloat) async -> UIImage? {
        // The style is part of the key: the same workout is drawn differently once the setting
        // changes, and a cached image of the other style must not come back.
        let key = "\(id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(Int(scale * 100))-\(style.rawValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let aspect = size.height > 1 ? size.width / size.height : 4
        let rect = MapImageRenderer.thumbnailMapRect(route: route.coordinates, aspect: aspect)
            ?? RouteGeometry.fitted(RouteGeometry.mapRect(for: route.coordinates.first ?? CLLocationCoordinate2D()))
        // A jump is drawn a touch thinner than the route: 2.4 pt is what a thumbnail has room
        // for, and the grey dashes stay legible beside it.
        let drawing = route.drawing(style)
        var lines = drawing.walked.map { RouteLine(coordinates: $0, color: color) }
        lines += drawing.jumps.map {
            RouteLine(coordinates: $0, color: RouteJump.uiColor, dash: RouteJump.dash, width: 1.8)
        }
        let image = await image(mapRect: rect, size: size, scale: scale,
                                routes: lines,
                                lineWidth: 2.4,
                                toneChroma: 0,
                                toneScale: 0.29,
                                toneOffset: 16)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
