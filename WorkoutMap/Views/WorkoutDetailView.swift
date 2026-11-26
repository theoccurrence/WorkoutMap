import SwiftUI
import MapKit
import CoreLocation
import Photos

struct WorkoutDetailView: View {
    let workout: Workout
    /// How the screen was opened. `pushed` fills its container edge to edge: the Workouts tab pushes it
    /// inside its own navigation stack, and so does the settings screen's list of edited workouts —
    /// inside *that* screen's sheet the sheet's own card is the card, so the detail fills it whole
    /// rather than insetting itself inside it (which left the system's fill showing as a grey bar under
    /// the card's bottom edge, measured: the band stays `(28, 28, 30)` whatever `presentationBackground`
    /// is told). The README says why the Workouts tab's push keeps the Duo's rail band empty rather than
    /// drawing a card in it.
    ///
    /// `card` is the map screen's own way in (the range bubble): the same screen drawn **in the map
    /// screen** like that screen's three menus (`MapTabView.menuLayer`), so the margin it keeps shows the
    /// *map* the card floats over — a sheet's own background runs flush to the display's bottom edge,
    /// which is the one side its card is not inset on, and no value of `presentationBackground` clears it
    /// (measured on iOS 27: `.clear` leaves a flat system fill, and `.thinMaterial` blurs that same fill
    /// rather than the map behind it).
    enum Presentation { case pushed, card }
    let presentation: Presentation
    /// What the back button does where the screen is drawn as a card of the map screen's own: there is
    /// no presentation to dismiss, so the screen that opened it closes it (`MapTabView`).
    var onClose: (() -> Void)? = nil
    /// The inset that puts this screen's rail on the status cluster's own column, **handed in** by the
    /// map screen where this is its card (`MapTabView` knows it — `usesVerticalControls` is the folded
    /// panel). A card cannot work it out for itself: its reader reports **no** window safe area at all on
    /// that panel (measured trailing 0), so the 84 pt the window reserves for its rail — the one thing
    /// that tells that display apart — is not visible from in here. `nil` for the pushed screen, which
    /// reads the window itself.
    var statusColumn: CGFloat? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var route = WorkoutRoute(coordinates: [])
    /// The two answers *Save* can give: the card is in the photo library, or it is not.
    @State private var saved = false
    @State private var failed = false
    /// The route-editing screen. Its edits are the app's own — the workout itself is untouched.
    @State private var showEdit = DebugLaunch.startEdit
    /// The screen's own map view, handed up by it: *Save* writes the image from that view's own
    /// rendering, which is the only place the routes and the 3D blocks are drawn with the depth
    /// between them (`ShareImageRenderer.image`).
    @State private var liveMapView: MKMapView?
    /// How tall the stats-and-source block under the map stands — measured, because the rail hangs on
    /// its top edge in every pose and on every display (see `body`).
    @State private var blockHeight: CGFloat = 0
    /// How the map is drawn, matching the map screen: the appearance setting against the
    /// system's own style.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance = .system
    /// Whether Satellite draws its labels layer — the same setting the map screen's panel writes.
    @AppStorage(MapMode.satelliteLabelsKey) private var satelliteLabels = true
    /// The jump rules — the same settings the map screen reads.
    @AppStorage(JumpSettings.distanceStyleKey) private var jumpDistanceStyle: RouteJumpStyle = JumpRules.standard.distanceStyle
    @AppStorage(JumpSettings.distanceThresholdKey) private var jumpDistanceThreshold: Double = JumpRules.standard.distanceThreshold
    @AppStorage(JumpSettings.speedStyleKey) private var jumpSpeedStyle: RouteJumpStyle = JumpRules.standard.speedStyle
    @AppStorage(JumpSettings.speedThresholdKey) private var jumpSpeedThreshold: Double = JumpRules.standard.speedThreshold
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    @ObservedObject private var modeColors = CategoryColorStore.shared
    /// The tone each jump rule draws in — the same choice the settings keep.
    @ObservedObject private var jumpColors = JumpColorStore.shared
    /// What the user changed about the route in the editor — read live, so an edit saved on the
    /// editor draws here the moment it closes.
    @ObservedObject private var editStore = RouteEditStore.shared

    private var edits: RouteEdits { editStore.edits(for: workout.id) }

    /// What the map frames: the fixes still drawn, so an erased stretch does not leave a hole of
    /// empty map beside what is left of the route.
    private var visibleCoordinates: [CLLocationCoordinate2D] { route.visible(edits) }

    /// The route as this screen draws it — and it is one of the two screens that shows the *flag*: a
    /// leg the user marked as ground they covered is drawn here as the jump it still is, in the
    /// route's own colour dotted, rather than as an ordinary part of the route the way the map and
    /// the list draw it. This is where the flag can be seen, and from here it can be changed.
    private var lines: [MapRouteLine] {
        MapRouteLine.lines(for: workout,
                           route: route,
                           rules: JumpRules(distanceStyle: jumpDistanceStyle,
                                            distanceThreshold: jumpDistanceThreshold,
                                            speedStyle: jumpSpeedStyle,
                                            speedThreshold: jumpSpeedThreshold),
                           color: modeColors.uiColor(for: workout.category),
                           tones: jumpColors.tones,
                           edits: edits,
                           showValidatedJumps: true)
    }

    /// The style the map is drawn in — `legacy`, the stored style, stays dark.
    private var mapInterfaceStyle: UIUserInterfaceStyle {
        mapAppearance.interfaceStyle(for: MapMode.stored, system: systemAppearance.style)
    }

    var body: some View {
        GeometryReader { proxy in
            // The card this screen was given: as the map screen's own card it has already been inset by
            // its caller (`MapTabView.menuLayer`, whose container ignores the safe area), so what it reads
            // here *is* the card; pushed, the screen is its container and that container's safe areas
            // belong to it.
            // The column the rail keeps: on the folded panel the status cluster's own centre, which is
            // further out than the app's `screenInset` (`statusColumnInsetFolded`, measured).
            let folded = proxy.safeAreaInsets.trailing >= Metrics.railInset
            let full = presentation == .card
                ? proxy.size
                : CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                         height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            // The rail's trailing inset: the status cluster's own column, measured from the **display**.
            // The two presentations differ by the box they are laid out in, and the probe says exactly
            // what that is — `pushed` fills the display (its 48.5 pt disc lands at 393.75..442.25, centre
            // **418.00**, on the cluster's own centre), while a card's box ends `menuCardInset` short of
            // it (the same `column` gave 385.75..434.25, 8 pt inboard), so a card takes that margin back
            // out again. Its reader reports no window safe area on that panel either, so there is nothing
            // else to allow for: 0 there, `menuCardInset` here.
            let column = statusColumn ?? (folded ? Metrics.statusColumnInsetFolded : Metrics.screenInset)
            let railTrailing = presentation == .card ? column - Metrics.menuCardInset : column
            ZStack(alignment: .bottomTrailing) {
                // The screen's content — the map with its overlays, the six numbers and the source
                // label — as the app's own card (`ShareCard`), which is also what *Save* renders into
                // the image it writes. The map takes what the numbers and the label leave rather than a
                // fixed share of the screen: the reference display gave it 59.96 % (measured), and it
                // gets that whenever the block below it is the size the reference had — but a smaller
                // screen, or a wider one that lays the same six cards out in fewer rows, can never leave
                // a card or the `*Data from …` label outside the card for want of the space. The block
                // is **measured** there: the rail hangs on its top edge, so the gap between the rail and
                // the info cards is the same one in every pose and on every display — which is what the
                // user asked for, and what the folded panel held sideways needed (there the rail used to
                // reach *into* the cards).
                ShareCard(subject: .workout(workout),
                          map: liveMap,
                          size: full,
                          // The screen carries where the numbers came from; the **image** carries the
                          // app's own badge (`ShareFooter`).
                          footerStyle: .source,
                          onBlockHeight: { blockHeight = $0 })

                // The screen's own rail — **Save**, **Edit** and **Back**, one round glass button
                // each — anchored to the **bottom**, just above the info cards, at the same gap the buttons
                // keep between themselves (`pillGap`, ~35 px at 3×), on the column the status cluster
                // keeps. Hanging from the bottom is what keeps it out of the status band's way: that
                // band's height is a number the folded panel does not report at all (measured: top 0),
                // and every attempt to guess it put the buttons among the icons.
                // What *Save* writes is laid out at the **display's** size either way: as the map
                // screen's own card this screen is inset by `Metrics.menuCardInset` on every side, so
                // the box it fills plus those margins is the display — and the file comes out the same
                // size from a card as from a pushed screen.
                actionRail(size: presentation == .card ? ShareImageRenderer.displaySize(for: full) : full)
                    .padding(.trailing, railTrailing)
                    .padding(.bottom, blockHeight + Metrics.pillGap)
            }
            // The black backdrop is a plain fill, and the *shape* it is cut to is the caller's: the
            // screen this is a card of is the one that knows where the card sits on the display and
            // therefore what each of its corners resolves to (`menuCardShape`), so it clips this whole
            // screen to that (`MapTabView.menuLayer`). Asking for the shape here as well would resolve
            // it a second time, differently — measured on the folded cover panel, whose display is
            // rounded differently at each corner, the two resolutions left the backdrop's sharper
            // corner showing as a black wedge behind the card's round one.
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #if DEBUG
            // WM_SAVE_CARD=1 — see `DebugLaunch.saveCard`. The simulator cannot tap *Save*, so the
            // card is written through the very call that button makes.
            .task {
                guard DebugLaunch.saveCard else { return }
                try? await Task.sleep(for: .seconds(DebugLaunch.saveCardDelay))
                await save(size: presentation == .card ? ShareImageRenderer.displaySize(for: full) : full)
            }
            #endif
            // Edge to edge, the way the map screen draws. Laid out inside the safe area, this
            // screen left the strip the system reserves for its own rail (the Duo's vertical bar
            // on the screen's side, in every pose but the unfolded portrait) as a band of empty
            // black with nothing in it, and the map stopped short of it too. Nothing here lives
            // in that rail — the back and share buttons are placed on the reader above, still
            // clear of it — so the whole screen belongs to the screen.
            //
            // As a card of the map screen's own it does **not**: the safe area read inside that card
            // is still the *window's*, so reaching for it there pushed the black backdrop out of the
            // frame it was given — measured on the folded cover panel, it ran off the top of the
            // display and came out 11.3 pt from the leading edge against 3.0 pt from the trailing one.
            // A card is geometry its own caller has already placed (`MapTabView.menuLayer`); it fills
            // exactly that and nothing more.
            .ignoresSafeArea(edges: presentation == .card ? [] : .all)
        }
        // As the map screen's own card the geometry is already the card's, and that screen's chrome —
        // the rail and the tab bar — is *faded* by it (`MapTabView.SystemChromeFade`) rather than hidden
        // from here: nothing about the bars is declared in this case, so the fade is the only thing
        // moving them.
        //
        // **No** `ignoresSafeArea(.top)` here, and that is the point: the screen is made full-bleed by
        // the `ZStack` above, and a second one *on the reader* took the window's own top inset away from
        // it — measured on the Pro Max, the reader then reported `top: 0` and the rail was placed 3 pt
        // *inside* the notch band (59 instead of 62).
        // This screen's own actions are drawn **in** it, in the `ZStack` above: a column at the
        // display's trailing edge, below the band the status elements keep, rather than in the two
        // corners the screen used to carry them in — a corner button was under the status cluster and
        // could not be tapped at all (the user's screenshot).
        .toolbar(presentation == .card ? .automatic : .hidden, for: .navigationBar)
        .toolbar(presentation == .card ? .automatic : .hidden, for: .tabBar)
        .task(id: workout.id) {
            route = RouteStore.shared.cached(workout.id) ?? WorkoutRoute(coordinates: [])
            let full = await RouteStore.shared.route(for: workout.hk)
            if !full.isEmpty { route = full }
        }
        .alert("Saved to Photos", isPresented: $saved) { Button("OK", role: .cancel) {} }
        .alert("Could not save", isPresented: $failed) { Button("OK", role: .cancel) {} }
        .fullScreenCover(isPresented: $showEdit) {
            WorkoutEditView(workout: workout)
        }
    }

    /// The map itself. Its frame and its overlays are the card's business (`ShareCard`), which is also
    /// the card *Save* renders — so the screen and the file show the same map, at the same size, with
    /// the same type, date and weather on it.
    private var liveMap: some View {
        RouteMapView(routes: lines,
                     camera: RouteGeometry.fittedRect(routes: [visibleCoordinates]).map { .fit($0) },
                     cameraToken: route.count,
                     mode: MapMode.stored,
                     satelliteLabels: satelliteLabels,
                     interfaceStyle: mapInterfaceStyle,
                     onMapViewReady: { liveMapView = $0 })
    }

    /// The three actions this screen carries: **Save**, **Edit** and **Back**, one round glass button
    /// each — the shape the map screen's own rail draws. *Save* writes what the screen is showing —
    /// the map with its overlays, the six numbers and the source label, and nothing of the rail or the
    /// status bar — straight to the photo library: there is no preview of the image, the screen is the
    /// preview.
    ///
    /// They are drawn **in** the screen rather than declared as toolbar items, which is a measured
    /// decision rather than a preference: the bar the rail's actions live in is the one the map screen
    /// **fades** while a card is up (`SystemChromeFade` — on the Duo the rail and the tab capsule are
    /// one view, and the capsule's band is where a card's own bottom edge reaches), so an item declared
    /// there would be invisible exactly when the card is on screen. What they *do* carry is the
    /// system's own glass button (`GlassCircleButton`), which is what makes them react to a tap the way
    /// the rail's do.
    private func actionRail(size: CGSize) -> some View {
        VStack(spacing: Metrics.pillGap) {
            GlassCircleButton(symbol: "arrow.down.to.line", label: "Save") {
                Task { await save(size: size) }
            }
            GlassCircleButton(symbol: "eraser", label: "Edit route") { showEdit = true }
            GlassCircleButton(symbol: "chevron.left", label: "Back") {
                if let onClose { onClose() } else { dismiss() }
            }
        }
    }

    /// Writes what the screen shows to the photo library: the map is the screen's own map view, taken
    /// off the view as it stands — the region it is framing, the camera it is in, and the routes inside
    /// MapKit's own render pass, with the 3D blocks occluding them — and the same card view the screen
    /// is made of is rendered over it, so the file is the screen without its buttons and without the
    /// status bar. Its footer is the app's badge rather than the screen's source line: the file is the
    /// app's, and the line belongs to the screen.
    private func save(size: CGSize) async {
        guard let image = ShareImageRenderer.image(subject: .workout(workout),
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

struct StatCard: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    // The unit shrinks with the value rather than **wrapping**: a card whose unit
                    // went onto a second line stood taller than the same card one width up, and the
                    // grid's own height with it — which is what a saved card, laid out at the
                    // display's width while the screen it was drawn from is a card of the map
                    // screen, turned into a footer pushed off its bottom edge (measured).
                    Text(unit)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.statCardRadius, style: .continuous))
    }
}
