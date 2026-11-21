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
    /// it sits on.
    @State private var railSize: CGSize = .zero
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
            // The rail's actions MUST stay system toolbar items. The system places them
            // itself — below the status cluster, clear of the camera cut-out and of a Live
            // Activity — and re-lays them out when the screen turns. Every attempt to draw
            // that column by hand (it was done for the folded panel once) lost exactly
            // that: a fixed offset drifts out of line with the tab bar below it, and the
            // clock and status badge run straight over it as soon as a Live Activity is
            // live.
            //
            // What the system does when the room runs out is *its* business: the screen names
            // every action and says which of them matter (`railToolbarItems`), and the system
            // folds the ones that may go. Two things were measured the hard way and are easy
            // to get wrong again:
            //
            // * One item whose *content* changes, instead of the actions themselves, does not
            //   work: the glass around the item is measured when it is inserted and never
            //   again, so it keeps the height of the state before — clipped glyphs one way
            //   round, an empty capsule the other. And an item's content cannot be animated at
            //   all: `.animation`/`.transition` inside a `ToolbarItem` never reach the UIKit
            //   bar, which simply swaps the content in one frame.
            // * The bar is not something to read back and answer. A screen that watched the
            //   system fold the map-style pill away and then declared a different set left
            //   that fold on screen for as long as the answer took — quarter of a second,
            //   every Live Activity. Priorities say which actions may go, and the system
            //   folds them in the same pass that makes the room.
            .toolbar(usesVerticalControls ? .visible : .hidden, for: .navigationBar)
            // The bar's own glass follows the map, too: the system draws it from the colour
            // scheme the toolbar is given, and `legacy` never asks for the light one.
            .toolbarColorScheme(controlsAreLight ? .light : .dark, for: .navigationBar, .bottomBar)
            .toolbar {
                if usesVerticalControls { railToolbarItems }
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
    private var isFoldedPanel: Bool { min(railSize.width, railSize.height) < 500 }

    // MARK: - Rail toolbar items

    /// The screen's actions for the system's vertical bar.
    ///
    /// The bar is handed every action the screen has, together with the *priority* that says
    /// which of them may be folded into the bar's own overflow menu when the room runs out —
    /// not a set of actions picked here from the size of the window.
    ///
    /// The ladder, first to go first: the calendar and the range (`.low`), then the map style,
    /// then the locate action and the share action (`.high`). Measured on the folded cover
    /// panel: upright, the rail fits every action while the status cluster is at rest and only
    /// the filters' worth once a Live Activity has grown it — so the system folds exactly the
    /// calendar and the range, in the pass that makes the room, and the map-style pill stays
    /// where it is; held sideways, where the rail is shorter still, it goes on to fold the map
    /// style and the locate action keeps its own button, as it did before. Nothing here is read
    /// back or answered, which is what used to leave the folded pill on screen for a moment.
    ///
    /// `visibilityPriority` is iOS 27; an older SDK gets the same actions with the system's own
    /// automatic priorities (and an older SDK has no Duo to put them in a vertical bar).
    @ToolbarContentBuilder
    private var railToolbarItems: some ToolbarContent {
        if #available(iOS 27.0, *) {
            ToolbarItem { shareToolbarItem }.visibilityPriority(.high)
            ToolbarItem { calendarToolbarItem }.visibilityPriority(.low)
            ToolbarItem { rangeToolbarItem }.visibilityPriority(.low)
            // Its own group: the system gives these a bubble of their own, aligned with the
            // bottom bar instead of the pill above — the map style above the locate action, the
            // same two-button pill the hand-placed column below draws. The map style is left at
            // the system's own priority so it goes before the locate action, not after it.
            ToolbarItem(placement: .bottomBar) { mapModeToolbarItem }
            ToolbarItem(placement: .bottomBar) { locateToolbarItem }.visibilityPriority(.high)
        } else {
            ToolbarItem { shareToolbarItem }
            ToolbarItem { calendarToolbarItem }
            ToolbarItem { rangeToolbarItem }
            ToolbarItem(placement: .bottomBar) { mapModeToolbarItem }
            ToolbarItem(placement: .bottomBar) { locateToolbarItem }
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

