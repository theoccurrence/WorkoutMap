import SwiftUI
import MapKit
import Photos

/// What the map screen's share button opens: the card that is about to be written, drawn as one of
/// that screen's own cards (`MapTabView.menuLayer`) rather than as a full-screen viewer — so the
/// margin around it shows the map it floats over — with a rail of two glass buttons on the right:
/// **Save**, which writes the card to the photo library, and **Back**, which puts it away.
///
/// The card is the app's own (`ShareCard`), and its map is a **live** one — the same routes, in the
/// same style, framed the way the map behind it is — so the card comes up with its map already
/// drawn, the way the workout card the range bubble opens does. Nothing is snapshotted until *Save*:
/// the image is rendered then, from the region the card is showing, so the file is what the card
/// promised and the wait is on the save rather than on the opening.
///
/// The image is laid out at the **display's** size rather than at the card's: a card of the map
/// screen is inset by `Metrics.menuCardInset` on every side, and the file is the screen's own image
/// whether it was written from a card or from a pushed screen (`ShareImageRenderer.displaySize`).
struct SharePreviewCard: View {
    /// The workouts the card's numbers are the sum over: the ones the map is showing, as the filter
    /// and the workout-type selection leave them.
    let workouts: [Workout]
    let rangeLabel: String
    /// What the card's map is framed to: the region the map screen is showing, so the card opens on
    /// the map the user was looking at.
    let mapRect: MKMapRect?
    /// The camera that screen was left in — the tilt and turn of its own 3D view — so the card opens
    /// on the **same** map rather than on a flat one. `nil`, or a flat pose, keeps the rect framing.
    let pose: MapPose?
    let routes: [MapRouteLine]
    /// The style the map is drawn in — the one the map behind the card shows.
    let mode: MapMode
    let interfaceStyle: UIUserInterfaceStyle
    /// The inset that puts the rail on the status cluster's own column, handed in by the map screen
    /// (see `WorkoutDetailView.statusColumn`).
    var statusColumn: CGFloat? = nil
    var onClose: () -> Void

    @Environment(\.displayScale) private var displayScale
    /// Whether Satellite draws its labels layer — the same setting the map screen's panel writes.
    @AppStorage(MapMode.satelliteLabelsKey) private var satelliteLabels = true
    /// The card's own map view, handed up by it: *Save* writes the image from that view's own
    /// rendering, which is the only place the routes and the 3D blocks are drawn with the depth
    /// between them (`ShareImageRenderer.image`).
    @State private var liveMapView: MKMapView?
    /// How tall the numbers-and-footer block stands: the rail hangs on its top edge, and the map the
    /// file covers is what the block leaves.
    @State private var blockHeight: CGFloat = 0
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            let column = statusColumn ?? Metrics.screenInset
            // A card's box ends `menuCardInset` short of the display, so the same column put its
            // button 8 pt inboard; the card takes that margin back out again (`WorkoutDetailView`).
            let railTrailing = column - Metrics.menuCardInset
            // What the image is written at: the box the card fills, plus the margin the card keeps.
            let display = ShareImageRenderer.displaySize(for: proxy.size)
            ZStack(alignment: .bottomTrailing) {
                // The live map draws MapKit's own *Maps* line, so the card asks for none — the same
                // division the detail screen makes.
                ShareCard(subject: .map(workouts: workouts, rangeLabel: rangeLabel),
                          map: liveMap,
                          size: proxy.size,
                          onBlockHeight: { blockHeight = $0 })
                rail(display: display)
                    .padding(.trailing, railTrailing)
                    .padding(.bottom, blockHeight + Metrics.pillGap)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background(Color.black)
            #if DEBUG
            // WM_SAVE_CARD=1 — see `DebugLaunch.saveCard`. The simulator cannot tap the rail's
            // *Save*, so the card is written through the very call that button makes.
            .task {
                guard DebugLaunch.saveCard else { return }
                try? await Task.sleep(for: .seconds(DebugLaunch.saveCardDelay))
                await save(size: display)
            }
            #endif
        }
        .alert("Saved to Photos", isPresented: $saved) { Button("OK", role: .cancel) {} }
        .alert("Could not save", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    /// The map the card is drawn over: the screen's own routes, framed to the region it was showing.
    ///
    /// The camera is applied on a **token** rather than on every change — the token is the route
    /// set's own size, which changes when the routes arrive and not while the card is up, so a pan
    /// of the card's map is not undone by the screen redrawing behind it.
    private var liveMap: some View {
        RouteMapView(routes: routes,
                     camera: initialCamera,
                     cameraToken: routes.reduce(0) { $0 + $1.coordinates.count },
                     mode: mode,
                     satelliteLabels: satelliteLabels,
                     interfaceStyle: interfaceStyle,
                     onMapViewReady: { liveMapView = $0 })
    }

    /// The camera the card's map opens on: the 3D view the screen behind it was left in, or — flat —
    /// the region the card was handed, framed to its own box.
    private var initialCamera: RouteMapView.Camera? {
        if let pose, !pose.isFlat { return .pose(pose) }
        return mapRect.map { .fit($0) }
    }

    private func rail(display: CGSize) -> some View {
        VStack(spacing: Metrics.pillGap) {
            GlassCircleButton(symbol: "arrow.down.to.line", label: "Save") {
                Task { await save(size: display) }
            }
            GlassCircleButton(symbol: "chevron.left", label: "Back") { onClose() }
        }
    }

    /// Writes the card — the map, the numbers and the footer, and nothing of the rail — to the photo
    /// library. The map is the card's own map view, taken off the view as it stands, so the file is the
    /// map the card is showing: tilted or flat, the routes in MapKit's own pass with the 3D blocks over
    /// them, and the card's layout rendered over it — without its buttons and without the status bar.
    private func save(size: CGSize) async {
        guard let image = ShareImageRenderer.image(subject: .map(workouts: workouts, rangeLabel: rangeLabel),
                                                   mapView: liveMapView,
                                                   size: size,
                                                   scale: displayScale) else {
            failed = true
            return
        }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { failed = true; return }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saved = true
        } catch {
            failed = true
        }
    }
}
