import SwiftUI
import MapKit
import CoreLocation

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

    @Environment(\.dismiss) private var dismiss
    @State private var route = WorkoutRoute(coordinates: [])
    @State private var showExport = DebugLaunch.openExport
    /// The route-editing screen. Its edits are the app's own — the workout itself is untouched.
    @State private var showEdit = DebugLaunch.startEdit
    @State private var visibleMapRect: MKMapRect?
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
            // A column measured from the **display** has two things to take back out, and the two
            // presentations differ by both: `pushed` is laid out in the display itself, while `card`
            // sits in the card's box — `menuCardInset` inside the display *and* inset by the window's
            // safe area (84 pt of it on the folded cover panel's trailing side, which the panel
            // reserves for its rail). Without the second one the card's rail stood 84 pt inboard of the
            // pushed screen's, which is exactly what the user saw.
            let column = folded ? Metrics.statusColumnInsetFolded : Metrics.screenInset
            let railTrailing = presentation == .card
                ? column - Metrics.menuCardInset - proxy.safeAreaInsets.trailing
                : column
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // The map takes what the stats and the source label leave rather than a fixed share of
                    // the screen: the reference display gave it 59.96 % (measured), and it gets that
                    // whenever the block below it is the size the reference had — but a smaller screen, or
                    // a wider one that lays the same six cards out in fewer rows, can never leave a card
                    // or the `*Data from …` label outside the card for want of the space.
                    mapSection
                    // The stats and the source label are **one block**, measured below: the rail hangs on
                    // its top edge, so the gap between the rail and the info cards is the same one in
                    // every pose and on every display — which is what the user asked for, and what the
                    // folded panel held sideways needed (there the rail used to reach *into* the cards).
                    VStack(spacing: 0) {
                        stats(landscape: full.width > full.height)
                            .padding(.horizontal, 23)
                            .padding(.top, 18)
                        footer
                            .padding(.horizontal, 23)
                            .padding(.top, 17)
                    }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { blockHeight = $0.height }
                }
                .frame(width: full.width, height: full.height, alignment: .top)

                // The screen's own rail — **Share**, **Edit** and **Back**, one round glass button each
                // — anchored to the **bottom**, just above the info cards, at the same gap the buttons
                // keep between themselves (`pillGap`, ~35 px at 3×), on the column the status cluster
                // keeps. Hanging from the bottom is what keeps it out of the status band's way: that
                // band's height is a number the folded panel does not report at all (measured: top 0),
                // and every attempt to guess it put the buttons among the icons.
                actionRail
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
        .fullScreenCover(isPresented: $showExport) {
            ExportPreviewView(workout: workout,
                              rangeLabel: workout.listDateText,
                              mapRect: visibleMapRect ?? RouteGeometry.fittedRect(routes: [visibleCoordinates]),
                              routes: lines,
                              mode: MapMode.stored,
                              interfaceStyle: mapInterfaceStyle)
        }
        .fullScreenCover(isPresented: $showEdit) {
            WorkoutEditView(workout: workout)
        }
    }

    /// The map, as tall as the rest of the screen leaves it. Nothing is clipped off the stats or the
    /// source label to make room for it: they are laid out at their own size and the map is what
    /// gives.
    private var mapSection: some View {
        RouteMapView(routes: lines,
                     camera: RouteGeometry.fittedRect(routes: [visibleCoordinates]).map { .fit($0) },
                     cameraToken: route.count,
                     mode: MapMode.stored,
                     satelliteLabels: satelliteLabels,
                     interfaceStyle: mapInterfaceStyle,
                     onRegionChange: { visibleMapRect = $0 })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) { mapOverlay }
            .overlay(alignment: .bottomTrailing) { weatherOverlay }
    }

    private var mapOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Image(systemName: workout.category.symbolName)
                    .font(.system(size: 33, weight: .regular))
                    .foregroundStyle(Palette.accent)
                Text(workout.category.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            Text(workout.detailDateText)
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
        .padding(.leading, 23)
        .padding(.bottom, 40)
    }

    private var weatherOverlay: some View {
        HStack(spacing: 14) {
            if let temperature = workout.temperature {
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium").font(.system(size: 15))
                    Text(Fmt.temperature(temperature)).font(.system(size: 17))
                }
            }
            if let humidity = workout.humidity {
                HStack(spacing: 5) {
                    Image(systemName: "humidity.fill").font(.system(size: 15))
                    Text(Fmt.humidity(humidity)).font(.system(size: 17))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.trailing, 22)
        .padding(.bottom, 44)
    }

    /// One of the six numbers under the map, and the unit it is read in.
    private struct Stat {
        let label: String
        let value: String
        let unit: String?
    }

    private var statItems: [Stat] {
        let distance = Fmt.distanceValue(workout.distance)
        return [
            Stat(label: "Time", value: Fmt.duration(workout.duration), unit: nil),
            Stat(label: "Distance", value: distance.value, unit: distance.unit),
            Stat(label: "Elevation",
                 value: workout.elevationAscended.map { Fmt.elevation($0) } ?? "--",
                 unit: "m"),
            Stat(label: "Active Calories",
                 value: workout.activeCalories.map { Fmt.caloriesValue($0) } ?? "--",
                 unit: "kcal"),
            Stat(label: "Avg. Pace",
                 value: Fmt.pace(workout.duration, meters: workout.distance),
                 unit: "/km"),
            Stat(label: "Avg. Heart Rate",
                 value: workout.avgHeartRate.map { Fmt.heartRate($0) } ?? "--",
                 unit: "bpm")
        ]
    }

    /// The six cards, in the grid the display asks for: **three rows of two standing up, two rows of
    /// three lying down**, so the block is never taller than it has to be. The map above gives up the
    /// room (`mapSection`), which is what puts all six of them and the `*Data from …` label inside the
    /// card in every orientation — the folded Duo lost the third row and the label altogether when the
    /// rows were fixed to the display's width and the map kept a fixed share of its height.
    private func stats(landscape: Bool) -> some View {
        let columns = landscape ? 3 : 2
        let items = statItems
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
        return VStack(spacing: Metrics.statCardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Metrics.statCardGap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        StatCard(label: item.label, value: item.value, unit: item.unit)
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("*Data from \(workout.sourceName)")
            .font(.system(size: 15))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three actions this screen carries: **Share**, **Edit** and **Back**, one round glass button
    /// each — the shape the map screen's own rail draws.
    ///
    /// They are drawn **in** the screen rather than declared as toolbar items, which is a measured
    /// decision rather than a preference: the bar the rail's actions live in is the one the map screen
    /// **fades** while a card is up (`SystemChromeFade` — on the Duo the rail and the tab capsule are
    /// one view, and the capsule's band is where a card's own bottom edge reaches), so an item declared
    /// there would be invisible exactly when the card is on screen. What they *do* carry is the
    /// system's own glass button (`GlassCircleButton`), which is what makes them react to a tap the way
    /// the rail's do.
    private var actionRail: some View {
        VStack(spacing: Metrics.pillGap) {
            GlassCircleButton(symbol: "square.and.arrow.up", label: "Share") { showExport = true }
            GlassCircleButton(symbol: "eraser", label: "Edit route") { showEdit = true }
            GlassCircleButton(symbol: "chevron.left", label: "Back") {
                if let onClose { onClose() } else { dismiss() }
            }
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
                    Text(unit)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.statCardRadius, style: .continuous))
    }
}
