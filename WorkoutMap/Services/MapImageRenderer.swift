import UIKit
import MapKit
import CoreLocation

struct RouteLine {
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
}

/// Renders MapKit snapshots with the app's dark muted style and optional route overlays.
final class MapImageRenderer {
    static let shared = MapImageRenderer()

    private let cache = NSCache<NSString, UIImage>()
    private static let ciContext = CIContext(options: nil)

    /// Applies saturation / contrast / brightness so the snapshot matches the
    /// grayscale, low-contrast look of the original app's map.
    /// Applies a linear tone curve (and optional desaturation) directly on sRGB
    /// pixels. Doing this by hand avoids Core Image's linear working space, which
    /// makes brightness/contrast behave unpredictably for the app's flat look.
    private func toneMapped(_ image: UIImage,
                            scale: CGFloat,
                            offset: CGFloat,
                            desaturate: Bool) -> UIImage {
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
            var value: CGFloat
            if desaturate {
                value = 0.299 * CGFloat(ptr[index])
                    + 0.587 * CGFloat(ptr[index + 1])
                    + 0.114 * CGFloat(ptr[index + 2])
            } else {
                value = CGFloat(ptr[index + 1])
            }
            let mapped = max(0, min(255, value * scale + offset))
            let byte = UInt8(mapped)
            ptr[index] = byte
            ptr[index + 1] = byte
            ptr[index + 2] = byte
        }
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    /// The map style the live map (`RouteMapView`) also uses, so an exported card
    /// shows the same map the user was looking at.
    static func configuration() -> MKStandardMapConfiguration {
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        return config
    }

    private func snapshot(mapRect: MKMapRect, size: CGSize, scale: CGFloat) async -> MKMapSnapshotter.Snapshot? {
        guard size.width > 1, size.height > 1 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.mapRect = mapRect
        options.size = size
        options.scale = scale
        options.preferredConfiguration = Self.configuration()
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)
        return try? await snapshotter.start()
    }

    /// Map + routes rendered into one image. `darkening` dims the map behind the
    /// route (1 = fully replaced by `darkeningColor`).
    func image(mapRect: MKMapRect,
               size: CGSize,
               scale: CGFloat,
               routes: [RouteLine],
               darkening: CGFloat = 0,
               darkeningColor: UIColor = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1),
               lineWidth: CGFloat = 7,
               toneScale: CGFloat = 1,
               toneOffset: CGFloat = 0,
               desaturate: Bool = true) async -> UIImage? {
        // MapKit draws its "Maps" attribution into the snapshot's bottom edge.
        // The original app shows no attribution in the card thumbnails, so the
        // snapshot is taken a little taller and that band is cropped off.
        let attributionBand: CGFloat = 14
        let snapshotSize = CGSize(width: size.width, height: size.height + attributionBand)
        guard let snapshot = await snapshot(mapRect: mapRect, size: snapshotSize, scale: scale) else { return nil }
        let base = toneMapped(snapshot.image, scale: toneScale, offset: toneOffset, desaturate: desaturate)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            base.draw(in: CGRect(x: 0, y: -attributionBand, width: size.width, height: snapshotSize.height))
            if darkening > 0 {
                darkeningColor.withAlphaComponent(darkening).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for route in routes where route.coordinates.count > 1 {
                cg.setStrokeColor(route.color.cgColor)
                cg.setLineWidth(lineWidth)
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
                   route: [CLLocationCoordinate2D],
                   color: UIColor,
                   size: CGSize,
                   scale: CGFloat) async -> UIImage? {
        let key = "\(id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(Int(scale * 100))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let aspect = size.height > 1 ? size.width / size.height : 4
        let rect = MapImageRenderer.thumbnailMapRect(route: route, aspect: aspect)
            ?? RouteGeometry.fitted(RouteGeometry.mapRect(for: route.first ?? CLLocationCoordinate2D()))
        let image = await image(mapRect: rect, size: size, scale: scale,
                                routes: [RouteLine(coordinates: route, color: color)],
                                darkening: 0,
                                darkeningColor: .black,
                                lineWidth: 2.4,
                                toneScale: 0.29,
                                toneOffset: 16,
                                desaturate: true)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
