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
    @State private var showSheet = DebugLaunch.openSheet
    @State private var showExport = DebugLaunch.openExport
    @State private var visibleMapRect: MKMapRect?
    /// The window's safe-area insets, reported by the map view.
    @State private var windowInsets: UIEdgeInsets = .zero
    /// The map screen's size: which way round the rail runs, and whether a short rail
    /// (folded landscape) still has room for the calendar and range actions.
    @State private var railSize: CGSize = .zero
    /// Which column the rail's pill carries. A state, and applied only once the window has
    /// stopped moving: changing this item's content while the system is relocating the rail
    /// makes it rebuild, and then the whole rail — the system's own tab bar included — is
    /// gone for a moment. That goes for the icons and the pill's height alike.
    @State private var railCompact = false
    @State private var railCompactTask: Task<Void, Never>?
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
            .onGeometryChange(for: CGSize.self) { $0.size } action: { railSize = $0 }
            .onChange(of: railSize) { _, _ in scheduleRailCompact() }
            .onChange(of: usesVerticalControls) { _, _ in scheduleRailCompact() }
            // The rail's actions MUST stay system toolbar items. The system places them
            // itself — below the status cluster, clear of the camera cut-out and of a Live
            // Activity — and re-lays them out when the screen turns. Every attempt to draw
            // that column by hand (it was done for the folded panel once) lost exactly
            // that: a fixed offset drifts out of line with the tab bar below it, and the
            // clock and status badge run straight over it as soon as a Live Activity is
            // live.
            //
            // Two things follow from that, both measured, both easy to get wrong again:
            //
            // * The *set* of items may only change once the window has stopped moving —
            //   see `scheduleRailCompact`. Changed mid-turn the bar host rebuilds the rail
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
            .toolbar {
                if usesVerticalControls {
                    ToolbarItem { shareToolbarItem }
                    if railCompact {
                        ToolbarItem { railOverflowToolbarItem }
                    } else {
                        ToolbarItem { calendarToolbarItem }
                        ToolbarItem { rangeToolbarItem }
                    }
                    // Its own group: the system gives the locate action a bubble of its
                    // own, aligned with the bottom bar instead of the pill above.
                    ToolbarItem(placement: .bottomBar) { locateToolbarItem }
                }
            }
        }
        .task { if !DebugLaunch.skipLocation { location.start() } }
        .task(id: reloadKey) { await reload() }
        .sheet(isPresented: $showSheet) {
            RangePickerSheet(selection: $selection, workouts: health.workouts)
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportPreviewView(workout: mostRecentInFilter,
                              rangeLabel: selection.label,
                              mapRect: exportRect,
                              routes: mapLines)
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
                         userLocation: location.location?.coordinate,
                         userDotColor: dotColor,
                         onRegionChange: { visibleMapRect = $0 },
                         onUserInteraction: { userMoved = true },
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
            toolbarGlyph(item.symbolName, tint: selected ? item.color : .white)
        }
        .buttonStyle(.plain)
        // A light wash behind the symbol; if the glass ignores the alpha the symbol alone
        // carries the colour.
        .glassEffect(selected ? .regular.tint(item.color.opacity(0.25)) : .regular, in: .circle)
        .accessibilityLabel(item.title)
    }

    /// The action column for the screens the system gives no side rail — the same three
    /// actions as the rail, in the same shape: one capsule and the locate circle beneath.
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

            Button {
                locate()
            } label: {
                toolbarGlyph("location.fill")
            }
            .buttonStyle(.plain)
            .glassEffect(in: Circle())
            .accessibilityLabel("Current position")
        }
    }

    private func toolbarButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarGlyph(symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toolbarGlyph(_ symbol: String, tint: Color = .white) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Metrics.toolbarIconSize, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: Metrics.toolbarButtonSize, height: Metrics.toolbarButtonSize)
            .contentShape(.circle)
    }

    private var rangeBubble: some View {
        Text(rangeLabel)
            .font(.system(size: 14))
            .foregroundStyle(Palette.rangeLabel)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: Metrics.controlHeight)
            .background(Palette.surface, in: Capsule())
    }

    /// True while the window sits on the Duo's folded cover panel. Its content column is
    /// far narrower than the unfolded inner panel's — 466 pt minus the rail's 84 pt
    /// against 951 pt — which is what tells the two panels apart in every orientation,
    /// where a plain height check cannot (folded portrait and unfolded landscape are
    /// nearly the same height).
    private var isFoldedPanel: Bool { min(railSize.width, railSize.height) < 500 }

    // MARK: - Rail toolbar items

    /// The folded landscape is the one rail where all seven buttons do not fit above each
    /// other, so the calendar and the range fold into one menu there.
    private var compactWanted: Bool {
        usesVerticalControls && isFoldedPanel && railSize.height < 540
    }

    /// Hands the rail its new set of items once the window has stopped moving — see the note
    /// above the toolbar. The change goes through `withAnimation`: inside a transaction the
    /// bar host updates its pill smoothly instead of swapping it in one frame. Without it the
    /// same change snaps, which is what the previous build looked like.
    private func scheduleRailCompact() {
        railCompactTask?.cancel()
        let wanted = compactWanted
        guard wanted != railCompact else { return }
        railCompactTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { railCompact = wanted }
        }
    }

    /// The rail's glyphs stay neutral; only the tab bar carries the accent.
    private var shareToolbarItem: some View {
        Button {
            showExport = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.white)
    }

    private var calendarToolbarItem: some View {
        Button {
            if kind != .all { showSheet = true }
        } label: {
            Label("Pick a period", systemImage: "calendar")
        }
        .disabled(kind == .all)
        .tint(.white)
    }

    private var rangeToolbarItem: some View {
        Menu {
            rangePicker
        } label: {
            Label("Range", systemImage: "line.3.horizontal.decrease")
        }
        .tint(.white)
    }

    private var locateToolbarItem: some View {
        Button {
            locate()
        } label: {
            Label("Current position", systemImage: "location.fill")
        }
        .tint(.white)
    }

    /// Calendar and range folded into one menu — the rail's answer to a short column.
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
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .tint(.white)
    }

    private var rangePicker: some View {
        Picker("Range", selection: kindBinding) {
            ForEach(RangeKind.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.inline)
    }

    private func toggle(_ item: WorkoutCategory) {
        withAnimation(.easeInOut(duration: 0.15)) {
            category = (category == item) ? nil : item
        }
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

