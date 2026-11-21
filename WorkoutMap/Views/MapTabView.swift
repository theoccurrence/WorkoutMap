import SwiftUI
import MapKit
import CoreLocation

struct MapTabView: View {
    @ObservedObject var health: HealthStore
    @ObservedObject var location: LocationProvider
    @Environment(\.displayScale) private var displayScale

    @State private var selection: RangeSelection = DebugLaunch.startSelection
        ?? MapTabView.defaultSelection(for: RangeKind.storedDefault)
    /// Walk is selected on open, so its pill reads as active from the start.
    @State private var category: WorkoutCategory? = DebugLaunch.startCategory ?? .walk
    @State private var loaded: [(Workout, [CLLocationCoordinate2D])] = []
    /// The camera move the map should perform; every `cameraToken` bump re-runs it.
    @State private var camera: RouteMapView.Camera?
    @State private var cameraToken = 0
    @State private var userMoved = false
    /// The map style. Kept in the settings, so the map opens on the style the user last
    /// picked; `legacy` — the grey map the app shipped with — until they pick another one.
    @AppStorage(MapMode.storedKey) private var mapMode: MapMode = DebugLaunch.startMapMode ?? MapMode.stored
    /// How the map is drawn: the system's own light or dark style, or one pinned in the
    /// settings.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance =
        DebugLaunch.startAppearance ?? MapAppearance.stored
    /// The system's own style, for `MapAppearance.system` — read from the screen, since the app
    /// itself is pinned to dark (see `SystemAppearance`).
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    /// The route the user last tapped. While one is selected the range bubble shows its own
    /// date and time instead of the range's label.
    @State private var tappedRouteID: String?
    @State private var showSheet = DebugLaunch.openSheet
    @State private var showModes = DebugLaunch.openModes
    @State private var showExport = DebugLaunch.openExport
    @State private var visibleMapRect: MKMapRect?
    /// The window's safe-area insets, reported by the map view.
    @State private var windowInsets: UIEdgeInsets = .zero
    /// The style the map was drawn in a moment ago, while its change is being washed over.
    /// MapKit swaps its tiles for the new style in one frame and cannot fade them — they are
    /// drawn by a Metal layer of the map's own, which `UIView.transition` cannot snapshot
    /// (measured) — so the screen lays a wash of the *old* look over the map for a moment: the
    /// map changes underneath it, and the new style arrives as the old one washes off, which is
    /// the transition Maps' own map makes.
    @State private var washStyle: UIUserInterfaceStyle = .dark
    /// How much of that wash is showing.
    @State private var washOpacity: Double = 0
    @State private var washTask: Task<Void, Never>?
    /// The map screen's size: which way round the rail runs, and which of the Duo's two panels
    /// it sits on. The folded cover panel's rail is the one with no room for the full set of
    /// actions, which is what `wantedRailSet` reads off it.
    @State private var railSize: CGSize = .zero
    /// The set of actions the rail declares. Which one it is is the only lever this screen has
    /// — the system places the items itself, and nothing inside one of them may be animated —
    /// and there are three of them.
    private enum RailSet {
        /// Share, the calendar and the range — and the map style above the locate action, in a
        /// bubble of their own. For a rail with room to spare.
        case full
        /// Share and one overflow menu carrying the calendar and the range — the map style and
        /// the locate action keep their own bubble. For a rail too tight for the full set.
        case filtersFolded
        /// Share and one overflow menu carrying the calendar, the range *and* the map style —
        /// the locate action alone in its bubble.
        case compact
    }

    /// The set the rail declares right now. Applied only once the window has stopped moving
    /// (`scheduleRailSet`): changing it while the system is relocating the rail makes the bar
    /// rebuild, and then the whole rail, the system's own tab bar included, is gone for a
    /// moment. The first set the rail is ever handed goes over at once instead: the rail must
    /// not open on a set the window cannot hold.
    @State private var railSet: RailSet = .full
    @State private var railSetTask: Task<Void, Never>?
    /// Whether the rail has ever been handed a set (see `scheduleRailSet`).
    @State private var railSetApplied = false
    /// The floating tab bar's capsule as insets from the window's bottom edge to its own
    /// bottom and top edges, measured from the bar so the overlays can line up with it.
    @State private var tabBarInsets: (bottom: CGFloat, top: CGFloat)?

    private var kind: RangeKind { selection.kind }

    /// Focus zoom for the locate button, and the much wider fallback zoom for a
    /// range that holds no route at all.
    private static let locateSpanMeters: Double = 1_200
    private static let emptySpanMeters: Double = 11_000
    /// How many routes streamed in from Health are handed to the map at once.
    private static let routeBatch = 20

    private var kindBinding: Binding<RangeKind> {
        Binding(get: { selection.kind },
                set: { newKind in
                    guard newKind != selection.kind else { return }
                    selection = MapTabView.defaultSelection(for: newKind)
                })
    }

    /// Switching range tab jumps to the current week / month / year, or all data.
    static func defaultSelection(for kind: RangeKind) -> RangeSelection {
        let calendar = AppCalendar.calendar
        let now = Date()
        switch kind {
        case .week: return .week(0)
        case .month: return .month(calendar.component(.month, from: now), calendar.component(.year, from: now))
        case .year: return .year(calendar.component(.year, from: now))
        case .all: return .all
        }
    }

    private var filtered: [Workout] {
        health.workouts.filter { selection.contains($0.start) && (category == nil || $0.category == category) }
    }

    private var mapLines: [MapRouteLine] {
        loaded
            .filter { $0.1.count > 1 }
            .map { MapRouteLine(id: $0.0.id.uuidString, coordinates: $0.1, color: $0.0.category.uiColor) }
    }

    private var hasData: Bool { !filtered.isEmpty }

    private var rangeLabel: String {
        hasData ? selection.label : selection.label + " \u{2014} No Data"
    }

    private var dotColor: UIColor { (category ?? .walk).uiColor }

    /// The style the map is drawn in. `legacy` is the grey map the app shipped with and stays
    /// dark whatever the setting says; every other mode follows it.
    private var mapInterfaceStyle: UIUserInterfaceStyle {
        mapAppearance.interfaceStyle(for: mapMode, system: systemAppearance.style)
    }

    /// Whether the screen's own controls are drawn in the light style. It follows the map: a map
    /// drawn light gets light controls, and `legacy` — which is the grey map the app shipped
    /// with and is never light — keeps the dark ones whatever the setting says.
    private var controlsAreLight: Bool { mapInterfaceStyle == .light }

    /// The colour of a glyph on those controls.
    private var controlGlyph: Color { controlsAreLight ? .black : .white }

    /// How strong the wash of the old look is: strong enough that the map reads as the style it
    /// was a moment ago, light enough that its streets still show through it.
    private static let washStrength: Double = 0.75
    /// How long the wash takes to come off.
    private static let washFade: TimeInterval = 0.45
    /// How many steps it comes off in.
    private static let washSteps = 18

    /// Washes the change of the map's light/dark style over with the style it came from, and
    /// takes it off again — the one transition MapKit leaves available (see `washStyle`).
    ///
    /// The fade is stepped rather than handed to `withAnimation`: a state that is taken back in
    /// the same turn it is set never reaches the screen at all (measured — the wash came and
    /// went unseen), and a transition needs the state it comes from to have been drawn.
    private func washAppearanceChange(from previous: UIUserInterfaceStyle) {
        washStyle = previous
        washTask?.cancel()
        washTask = Task { @MainActor in
            washOpacity = Self.washStrength
            let step = Self.washFade / Double(Self.washSteps)
            for index in 1...Self.washSteps {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                // Ease out: most of the way off in the first half of the fade.
                let progress = Double(index) / Double(Self.washSteps)
                washOpacity = Self.washStrength * (1 - progress) * (1 - progress)
            }
            washOpacity = 0
        }
    }

    /// The workout behind the tapped route, while the map is still showing it.
    private var tappedWorkout: Workout? {
        guard let tappedRouteID else { return nil }
        return loaded.first { $0.0.id.uuidString == tappedRouteID }?.0
    }

    private var centersOn: CLLocationCoordinate2D? {
        if let loc = location.location?.coordinate { return loc }
        return loaded.first?.1.first
    }

    private var mostRecentInFilter: Workout? {
        filtered.first ?? health.workouts.first
    }

    private var reloadKey: String {
        "\(selection)|\(category?.rawValue ?? "all")|\(health.workouts.count)|\(location.location == nil)"
    }

    var body: some View {
        // A navigation container on purpose: it is what lets the system place the
        // screen's actions in the Duo's vertical bar (next to the tab bar, above it,
        // scaling with the status cluster) instead of a hand-placed overlay.
        NavigationStack {
            ZStack(alignment: .top) {
                Palette.surface.ignoresSafeArea()
                map
            }
            .onChange(of: mapInterfaceStyle) { previous, _ in washAppearanceChange(from: previous) }
            // The tab bar is the app's own control rather than this screen's, so it is told
            // which style this screen is drawing its own in.
            .onAppear { ControlAppearance.shared.setLight(controlsAreLight) }
            .onChange(of: controlsAreLight) { _, light in ControlAppearance.shared.setLight(light) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { railSize = $0 }
            // A turn, a fold of the phone or a move to the other display: the rail's set is
            // re-decided from the size it moved to (`wantedRailSet`), and nothing here reads
            // the system's rail.
            .onChange(of: railSize) { _, _ in scheduleRailSet() }
            .onChange(of: usesVerticalControls) { _, _ in scheduleRailSet() }
            .onChange(of: windowInsets) { _, _ in scheduleRailSet() }
            // The rail's actions MUST stay system toolbar items. The system places them
            // itself — below the status cluster, clear of the camera cut-out and of a Live
            // Activity — and re-lays them out when the screen turns. Every attempt to draw
            // that column by hand (it was done for the folded panel once) lost exactly
            // that: a fixed offset drifts out of line with the tab bar below it, and the
            // clock and status badge run straight over it as soon as a Live Activity is
            // live.
            //
            // Three things follow from that, all measured, all easy to get wrong again:
            //
            // * The *set* has to be one the window can hold: the system folds what does not
            //   fit into an overflow of its own, and on the folded panel it folds the map
            //   style and the locate action — the pill this screen is for — away with it. A
            //   set that only just fits is therefore not safe, and the rail decides which one
            //   to declare from the window's own size rather than by watching for the fold
            //   (`wantedRailSet`). Watching for it leaves the folded pill on screen for as
            //   long as the fold takes to be answered, which is what a Live Activity growing
            //   the status cluster used to show for a moment.
            // * The set may only change once the window has stopped moving —
            //   see `scheduleRailSet`. Changed mid-turn the bar host rebuilds the rail
            //   while the system is still relocating it, and the whole rail, the system's
            //   own tab bar included, is missing for a moment. Changed at rest the host
            //   brings the new pill in with an animation of its own, and that is the only
            //   animation available here.
            // * One item whose *content* changes, instead of a set that changes, does not
            //   work either: the glass around the item is measured when it is inserted and
            //   never again, so it keeps the height of the state before — clipped glyphs
            //   one way round, an empty capsule the other. And an item's content cannot be
            //   animated at all: `.animation`/`.transition` inside a `ToolbarItem` never
            //   reach the UIKit bar, which simply swaps the content in one frame.
            .toolbar(usesVerticalControls ? .visible : .hidden, for: .navigationBar)
            // The bar's own glass follows the map, too: the system draws it from the colour
            // scheme the toolbar is given, and `legacy` never asks for the light one.
            .toolbarColorScheme(controlsAreLight ? .light : .dark, for: .navigationBar, .bottomBar)
            .toolbar {
                if usesVerticalControls {
                    ToolbarItem { shareToolbarItem }
                    if railSet == .full {
                        ToolbarItem { calendarToolbarItem }
                        ToolbarItem { rangeToolbarItem }
                    } else {
                        ToolbarItem { railOverflowToolbarItem }
                    }
                    // Its own group: the system gives these a bubble of their own, aligned
                    // with the bottom bar instead of the pill above — the map style above
                    // the locate action, the same two-button pill the hand-placed column
                    // below draws.
                    //
                    // The map style only gets that bubble while the rail has room for two
                    // items in it. On the short rail the system folds a second bubble into an
                    // overflow of its own, so the style moves into the menu above instead and
                    // the locate action keeps its own button to itself. When the system is the
                    // one folding — a Live Activity taking the room — the style stays here and
                    // the calendar and the range go into the menu instead: this pill is what
                    // the screen is for, the filters are one tap deeper.
                    if railSet != .compact {
                        ToolbarItem(placement: .bottomBar) { mapModeToolbarItem }
                    }
                    ToolbarItem(placement: .bottomBar) { locateToolbarItem }
                }
            }
        }
        // The wash covers the screen — the map, the overlays and the rail — so the whole thing
        // turns at once: MapKit cannot fade its tiles and the bar cannot fade its glass, so the
        // change is made under the wash and the old look comes off with it.
        .overlay {
            Color(washStyle == .light ? .white : .black)
                .opacity(washOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .task {
            if let start = DebugLaunch.startMapMode { mapMode = start }
            if let start = DebugLaunch.startAppearance { mapAppearance = start }
            if !DebugLaunch.skipLocation { location.start() }
        }
        .task(id: reloadKey) { await reload() }
        .sheet(isPresented: $showSheet) {
            RangePickerSheet(selection: $selection, workouts: health.workouts)
        }
        .sheet(isPresented: $showModes) {
            MapModeSheet(mode: $mapMode,
                         appearance: mapAppearance,
                         systemStyle: systemAppearance.style)
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportPreviewView(workout: mostRecentInFilter,
                              rangeLabel: rangeBubbleText,
                              mapRect: exportRect,
                              routes: mapLines,
                              mode: mapMode,
                              interfaceStyle: mapInterfaceStyle)
        }
    }

    private var exportRect: MKMapRect? {
        visibleMapRect ?? RouteGeometry.fittedRect(routes: loaded.map { $0.1 })
    }

    /// True on a screen whose system chrome lives in a side rail (the iPhone Duo, inner
    /// and outer display, either orientation): the map fills every safe area and the
    /// actions become real toolbar items in the system's own vertical bar.
    private var usesVerticalControls: Bool {
        max(windowInsets.left, windowInsets.right) >= Metrics.railInset
    }

    private var isPortraitLayout: Bool { railSize.height >= railSize.width }

    /// The filters keep to the side opposite the toolbar. The rail sits on the camera
    /// cut-out's side, which is the left one when the phone is folded and turned that way.
    private var filtersOnTrailingEdge: Bool { windowInsets.left > windowInsets.right }

    /// The distance from the screen's bottom edge to the filters' bottom edge.
    private var filterBottomInset: CGFloat {
        // Sideways on the folded panel the rail's own edge is the one to keep to: it sits
        // at the rail's normal 23 pt in the rotation with the rail on the left, and the
        // camera cut-out pushes it far up in the other one. The bar cannot be measured
        // there either way — a parked copy of it is left in the window and reads 105 pt
        // where the bar really is at 23 — so the filters take the edge the rail has in
        // every folded orientation rather than follow that reading.
        if isFoldedPanel, !isPortraitLayout, usesVerticalControls {
            return Metrics.filterInsetFoldedLandscape
        }
        // Down a side the filters follow the bar's own bottom edge — level with its last
        // button. With the bar running along the bottom they end level with the locate
        // action instead, on the bar's top edge.
        if usesVerticalControls {
            return barInset(Metrics.filterInsetRailPortrait, at: \.bottom)
        }
        return toolbarBottomInset
    }

    /// The hand-placed toolbar's bottom edge: it sits on the tab bar's top edge, so the
    /// screen without a side rail gets the same flush column the rail gives the others.
    private var toolbarBottomInset: CGFloat {
        barInset(Metrics.toolbarButtonSize + Metrics.pillGap, at: \.top) + Metrics.pillGap
    }

    /// The measured bar inset, but only while it is plausible. A rotation can leave a parked
    /// copy of the bar in the window at a stale position, and following it would fling the
    /// overlays across the screen — the fallback keeps them where they belong instead.
    private func barInset(_ fallback: CGFloat, at edge: KeyPath<(bottom: CGFloat, top: CGFloat), CGFloat>) -> CGFloat {
        guard let measured = tabBarInsets?[keyPath: edge] else { return fallback }
        return (0...160).contains(measured) ? measured : fallback
    }


    private var map: some View {
        ZStack(alignment: .top) {
            RouteMapView(routes: mapLines,
                         camera: camera,
                         cameraToken: cameraToken,
                         mode: mapMode,
                         interfaceStyle: mapInterfaceStyle,
                         userLocation: location.location?.coordinate,
                         userHeading: location.heading,
                         userCourse: location.course,
                         userDotColor: dotColor,
                         onRegionChange: { visibleMapRect = $0 },
                         onUserInteraction: { userMoved = true },
                         onRouteTap: { tappedRouteID = $0 },
                         onSafeAreaChange: { if windowInsets != $0 { windowInsets = $0 } },
                         onTabBarInsets: { bottom, top in
                             if tabBarInsets == nil || tabBarInsets! != (bottom, top) {
                                 tabBarInsets = (bottom, top)
                             }
                         })
                .ignoresSafeArea()

            VStack(spacing: 0) {
                rangeBubble
                    // Pinned to the display edge: the same 18 pt below the top of the screen
                    // that it had below the grey bar, in every layout.
                    .padding(.top, 18)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    if filtersOnTrailingEdge { Spacer(minLength: 0) }
                    categoryFilters
                        .environment(\.colorScheme, controlsAreLight ? .light : .dark)
                        .id(controlsAreLight)
                    if !filtersOnTrailingEdge { Spacer(minLength: 0) }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, filterBottomInset)
            }
            // Measured against the display edges rather than the safe area: the bubble keeps
            // the gap below the top of the screen that it has below the grey bar in the
            // reference, and the overlays line up with the tab bar's own edges.
            .ignoresSafeArea()

            // Screens without a side rail get no vertical toolbar from the system, so the
            // same column is placed by hand: the action capsule with the locate circle
            // directly beneath it, flush above the tab bar.
            if !usesVerticalControls {
                mapToolbar
                    .environment(\.colorScheme, controlsAreLight ? .light : .dark)
                    .id(controlsAreLight)
                    .padding(.trailing, Metrics.screenInset)
                    .padding(.bottom, toolbarBottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .ignoresSafeArea()
            }

        }
    }

    /// Walk / Run / Ride as toolbar circles — symbol only, walk at the top, the selected
    /// one carrying its own colour. They sit opposite the toolbar.
    private var categoryFilters: some View {
        VStack(spacing: Metrics.pillGap) {
            ForEach(WorkoutCategory.allCases) { item in
                filterButton(item)
            }
        }
    }

    private func filterButton(_ item: WorkoutCategory) -> some View {
        let selected = category == item
        return Button {
            toggle(item)
        } label: {
            toolbarGlyph(item.symbolName, tint: selected ? item.color : controlGlyph)
        }
        .buttonStyle(.plain)
        // A light wash behind the symbol; if the glass ignores the alpha the symbol alone
        // carries the colour.
        .glassEffect(selected ? .regular.tint(item.color.opacity(0.25)) : .regular, in: .circle)
        .accessibilityLabel(item.title)
    }

    /// The action column for the screens the system gives no side rail — the same actions as
    /// the rail, in the same shape: the pill of screen actions, and beneath it the two-button
    /// pill Maps carries as well, the map style above the locate action.
    private var mapToolbar: some View {
        VStack(spacing: Metrics.pillGap) {
            VStack(spacing: 0) {
                toolbarButton("square.and.arrow.up", label: "Share") { showExport = true }
                toolbarButton("calendar", label: "Pick a period") {
                    if kind != .all { showSheet = true }
                }
                .disabled(kind == .all)
                Menu {
                    rangePicker
                } label: {
                    toolbarGlyph("line.3.horizontal.decrease")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Range")
            }
            .padding(.vertical, 4)
            .glassEffect(in: Capsule())

            VStack(spacing: 0) {
                Button {
                    showModes = true
                } label: {
                    toolbarGlyph("map.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Map mode")

                Button {
                    locate()
                } label: {
                    toolbarGlyph("location.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Current position")
            }
            .padding(.vertical, 4)
            .glassEffect(in: Capsule())
        }
    }

    private func toolbarButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarGlyph(symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toolbarGlyph(_ symbol: String, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Metrics.toolbarIconSize, weight: .regular))
            .foregroundStyle(tint ?? controlGlyph)
            .frame(width: Metrics.toolbarButtonSize, height: Metrics.toolbarButtonSize)
            .contentShape(.circle)
    }

    /// What the bubble reads: the tapped route's own date and time while one is selected — the
    /// tap lands on the map, the map reports the route, the bubble names it — and the range's
    /// label otherwise.
    private var rangeBubbleText: String {
        tappedWorkout.map { Fmt.routeDateTime.string(from: $0.start) } ?? rangeLabel
    }

    private var rangeBubble: some View {
        Text(rangeBubbleText)
            .font(.system(size: 14))
            .foregroundStyle(controlsAreLight ? Palette.rangeLabelLight : Palette.rangeLabel)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: Metrics.controlHeight)
            .background(controlsAreLight ? Palette.surfaceLight : Palette.surface, in: Capsule())
    }

    /// True while the window sits on the Duo's folded cover panel. Its content column is
    /// far narrower than the unfolded inner panel's — 466 pt minus the rail's 84 pt
    /// against 951 pt — which is what tells the two panels apart in every orientation,
    /// where a plain height check cannot (folded portrait and unfolded landscape are
    /// nearly the same height).
    ///
    /// It also chooses the rail's set: the cover panel's rail is the one with no room for the
    /// full set of actions (see `wantedRailSet`).
    private var isFoldedPanel: Bool { min(railSize.width, railSize.height) < 500 }

    // MARK: - Rail toolbar items

    /// The folded landscape is the one rail where all seven buttons do not fit above each
    /// other, so the calendar and the range fold into one menu there and the map style joins
    /// them: the rail has no room for a second bubble beside the locate action.
    private var shortRailWanted: Bool {
        guard usesVerticalControls else { return false }
        return isFoldedPanel && railSize.height < 540
    }

    /// The set the rail should be declaring, decided from the window's own geometry.
    ///
    /// The system folds whatever it is handed and does not fit into an overflow of its own, and
    /// on the folded panel that is the map style and the locate action — the pill this screen is
    /// for. So a tight rail declares a set that fits instead, and it decides that from the size
    /// of the window rather than by watching the system fold: a set that only *just* fits shows
    /// the wrong pill for as long as the fold takes to be noticed, and that is what used to be
    /// on screen for a moment when a Live Activity grew the status cluster.
    ///
    /// * the short rail — the folded panel held sideways — declares `compact`;
    /// * the folded cover panel's rail, upright, declares `filtersFolded`: its status cluster is
    ///   a *vertical* strip that takes most of the rail's height, which leaves the rail room for
    ///   the filters' set but not for the full one, and a Live Activity in it only takes more;
    /// * anything else — a rail with room — declares `full`.
    private var wantedRailSet: RailSet {
        if shortRailWanted { return .compact }
        return isFoldedPanel ? .filtersFolded : .full
    }

    /// Hands the rail its set once the window has stopped moving — see the note above the
    /// toolbar. The change goes through `withAnimation`: inside a transaction the bar host
    /// brings the new pill in with an animation of its own instead of swapping it in one frame,
    /// and that animation is all there is — the system owns this bar. The first set the rail is
    /// ever handed goes over at once: the rail has just been built and is not going anywhere,
    /// and it must not spend a moment declaring a set the window cannot hold.
    private func scheduleRailSet() {
        railSetTask?.cancel()
        let wanted = wantedRailSet
        guard wanted != railSet else { return }
        let apply = {
            withAnimation(.easeInOut(duration: 0.2)) { railSet = wanted }
            railSetApplied = true
        }
        guard railSetApplied else {
            apply()
            return
        }
        railSetTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            apply()
        }
    }

    /// The rail's glyphs stay neutral; only the tab bar carries the accent.
    private var shareToolbarItem: some View {
        Button {
            showExport = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(controlGlyph)
    }

    private var calendarToolbarItem: some View {
        Button {
            if kind != .all { showSheet = true }
        } label: {
            Label("Pick a period", systemImage: "calendar")
        }
        .disabled(kind == .all)
        .tint(controlGlyph)
    }

    private var rangeToolbarItem: some View {
        Menu {
            rangePicker
        } label: {
            Label("Range", systemImage: "line.3.horizontal.decrease")
        }
        .tint(controlGlyph)
    }

    private var mapModeToolbarItem: some View {
        Button {
            showModes = true
        } label: {
            Label("Map mode", systemImage: "map.fill")
        }
        .tint(controlGlyph)
    }

    private var locateToolbarItem: some View {
        Button {
            locate()
        } label: {
            Label("Current position", systemImage: "location.fill")
        }
        .tint(controlGlyph)
    }

    /// Calendar and range folded into one menu — the rail's answer to a short column. On the
    /// short rail the style joins them, because there is no room for a second bubble beside the
    /// locate action; when the system is the one folding, the style keeps its own bubble.
    private var railOverflowToolbarItem: some View {
        Menu {
            Button {
                if kind != .all { showSheet = true }
            } label: {
                Label("Pick a period", systemImage: "calendar")
            }
            .disabled(kind == .all)
            Menu {
                rangePicker
            } label: {
                Label("Range", systemImage: "line.3.horizontal.decrease")
            }
            if railSet == .compact {
                Button {
                    showModes = true
                } label: {
                    Label("Map mode", systemImage: "map.fill")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .tint(controlGlyph)
    }

    private var rangePicker: some View {
        Picker("Range", selection: kindBinding) {
            ForEach(RangeKind.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.inline)
    }

    /// Picks a Walk / Run / Ride filter. Tapping the one that is already on does nothing at
    /// all: it must not turn the filter off — an empty filter falls back to walking's routes —
    /// and it must not re-zoom the map the way a real change does.
    private func toggle(_ item: WorkoutCategory) {
        guard category != item else { return }
        withAnimation(.easeInOut(duration: 0.15)) { category = item }
    }

    /// The locate button: centre on the current position. Without a fix there is
    /// nothing to focus, so it falls back to the route fit.
    private func locate() {
        userMoved = false
        guard let coordinate = location.location?.coordinate else {
            fitContent()
            return
        }
        camera = .center(coordinate, spanMeters: Self.locateSpanMeters)
        cameraToken += 1
    }

    private func fitContent() {
        if let rect = RouteGeometry.fittedRect(routes: loaded.map { $0.1 }) {
            camera = .fit(rect)
        } else if let coordinate = centersOn {
            camera = .center(coordinate, spanMeters: Self.emptySpanMeters)
        } else {
            camera = nil
        }
        cameraToken += 1
    }

    private func reload() async {
        userMoved = false
        tappedRouteID = nil
        let list = filtered
        let cached = await RouteStore.shared.cachedRoutes(for: list.map(\.id))
        loaded = list.compactMap { workout in cached[workout.id].map { (workout, $0) } }
        fitContent()

        let missing = list.filter { cached[$0.id] == nil }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (Workout, [CLLocationCoordinate2D]).self) { group in
            for workout in missing {
                group.addTask { (workout, await RouteStore.shared.route(for: workout.hk)) }
            }
            // Applying every arrival on its own re-tessellates all the routes already
            // on screen once per arrival — that is what made the Year and All ranges
            // crawl while they loaded. They are applied in batches instead.
            var arrived: [(Workout, [CLLocationCoordinate2D])] = []
            for await result in group {
                guard !result.1.isEmpty else { continue }
                arrived.append(result)
                guard arrived.count >= Self.routeBatch else { continue }
                merge(arrived)
                arrived.removeAll(keepingCapacity: true)
                if !userMoved { fitContent() }
            }
            if !arrived.isEmpty {
                merge(arrived)
                if !userMoved { fitContent() }
            }
        }
    }

    private func merge(_ batch: [(Workout, [CLLocationCoordinate2D])]) {
        let ids = Set(batch.map { $0.0.id })
        loaded.removeAll { ids.contains($0.0.id) }
        loaded.append(contentsOf: batch)
    }
}

