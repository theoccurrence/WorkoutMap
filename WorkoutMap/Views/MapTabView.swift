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
    @State private var loaded: [(Workout, WorkoutRoute)] = []
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
    /// How the two softer jump rules are set — what counts as a jump, and how it is drawn. Read
    /// live, so a change in the settings redraws the routes at once.
    @AppStorage(JumpSettings.distanceStyleKey) private var jumpDistanceStyle: RouteJumpStyle = JumpRules.standard.distanceStyle
    @AppStorage(JumpSettings.distanceThresholdKey) private var jumpDistanceThreshold: Double = JumpRules.standard.distanceThreshold
    @AppStorage(JumpSettings.speedStyleKey) private var jumpSpeedStyle: RouteJumpStyle = JumpRules.standard.speedStyle
    @AppStorage(JumpSettings.speedThresholdKey) private var jumpSpeedThreshold: Double = JumpRules.standard.speedThreshold
    /// The system's own style, for `MapAppearance.system` — read from the screen, since the app
    /// itself is pinned to dark (see `SystemAppearance`).
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    /// The colours the three modes are drawn in — the routes, the position dot and its cone,
    /// and the filter buttons — as the settings keep them.
    @ObservedObject private var modeColors = CategoryColorStore.shared
    /// The route the user last tapped. While one is selected the range bubble shows its own
    /// date and time instead of the range's label.
    @State private var tappedRouteID: String?
    @State private var showRange = DebugLaunch.openSheet
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

    // MARK: - Explorer

    /// The "where have I never been" index, built over **every** workout rather than the range
    /// the map is filtered to.
    @StateObject private var coverage = CoverageStore()
    @State private var showPlanner = DebugLaunch.openPlanner
    @State private var planMode: PlanMode = DebugLaunch.planMode ?? .loop
    @State private var planKilometers: Double = DebugLaunch.planKilometers ?? 5
    @State private var planDestination: PlanDestination?
    /// The destination pin on the map. One at a time: a new press replaces it.
    @State private var droppedPin: CLLocationCoordinate2D? = DebugLaunch.fakePin
    /// What the pin's info bubble says, once the geocoder has answered.
    @State private var pinPlace: PinPlace?
    /// How many routes the explorer offers at once, and how tight it keeps them — the two
    /// things the settings let the user steer.
    @AppStorage(ExploreOptions.routeCountKey) private var exploreRouteCount: Int = ExploreOptions.routeCountDefault
    @AppStorage(ExploreOptions.shapeKey) private var exploreShape: Double = ExploreOptions.shapeDefault
    /// How much of the route should be new ground — see `ExploreOptions.minimumNewKey`.
    @AppStorage(ExploreOptions.minimumNewKey) private var exploreMinimumNew: Double = ExploreOptions.minimumNewDefault
    @State private var plan: RoutePlan?
    /// Which of the plan's routes is the one; 0 is the primary.
    @State private var selectedRoute = 0
    @State private var isPlanning = false
    /// True once Go was tapped: the route stays on the map until a new plan is started or the
    /// app is relaunched.
    @State private var planActive = false
    /// How far up the result card is being pulled right now, and how far it is parked once it has
    /// been flicked away. The card follows the thumb rather than running a fixed animation on
    /// release — a swipe that does not keep up with the finger does not feel like a swipe — so
    /// both live in one offset that the drag writes and the release animates.
    @State private var cardOffset: CGFloat = 0
    @State private var cardParked = false
    /// How far the card has to travel to be clear of the screen, measured from the card itself.
    @State private var cardTravel: CGFloat = 200
    @State private var planTask: Task<Void, Never>?

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
        loaded.flatMap {
            MapRouteLine.lines(for: $0.0,
                               route: $0.1,
                               rules: jumpRules,
                               color: modeColors.uiColor(for: $0.0.category))
        }
    }

    /// The explorer's planned route and its alternates, as map lines: the selected one in the
    /// bright blue with a casing under it, the others washed out — the way Maps draws them.
    private var plannedLines: [MapRouteLine] {
        guard let plan else { return [] }
        var lines: [MapRouteLine] = []
        for (index, route) in plan.routes.enumerated() where route.coordinates.count > 1 {
            if index == selectedRoute {
                lines.append(MapRouteLine(id: "plan-\(index)-casing",
                                          coordinates: route.coordinates,
                                          color: RouteBlue.uiCasing,
                                          width: 8))
                lines.append(MapRouteLine(id: "plan-\(index)",
                                          coordinates: route.coordinates,
                                          color: RouteBlue.uiPrimary,
                                          width: 5))
            } else if !planActive {
                // Once Go has been tapped the map is the route being walked and nothing else:
                // the alternates were a choice, and the choice has been made.
                lines.append(MapRouteLine(id: "plan-\(index)",
                                          coordinates: route.coordinates,
                                          color: RouteBlue.uiAlternate,
                                          width: 4))
            }
        }
        return lines
    }

    /// Whether the explorer reads as on: its sheet is open, it is planning, or it has a route
    /// on the map. The button carries its own colour then, independent of Walk / Run / Ride.
    private var exploreIsOn: Bool { showPlanner || isPlanning || plan != nil }

    /// Where a plan starts: the current fix, the middle of the map, or the newest route's own
    /// start — whichever there is.
    private var planStart: CLLocationCoordinate2D? {
        if let coordinate = location.location?.coordinate { return coordinate }
        if let rect = visibleMapRect {
            return MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        }
        return centersOn
    }

    /// The map's own area, so the destination search is biased to what the user is looking at.
    private var currentRegion: MKCoordinateRegion? {
        guard let rect = visibleMapRect else { return nil }
        let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let perMeter = MKMapPointsPerMeterAtLatitude(center.latitude)
        guard perMeter > 0 else { return nil }
        return MKCoordinateRegion(center: center,
                                  latitudinalMeters: rect.size.height / perMeter,
                                  longitudinalMeters: rect.size.width / perMeter)
    }

    private var hasData: Bool { !filtered.isEmpty }

    private var rangeLabel: String {
        hasData ? selection.label : selection.label + " \u{2014} No Data"
    }

    private var dotColor: UIColor { modeColors.uiColor(for: category ?? .walk) }

    /// The two jump rules as the settings have them.
    private var jumpRules: JumpRules {
        JumpRules(distanceStyle: jumpDistanceStyle,
                  distanceThreshold: jumpDistanceThreshold,
                  speedStyle: jumpSpeedStyle,
                  speedThreshold: jumpSpeedThreshold)
    }

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
        return loaded.first?.1.coordinates.first
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
            if let shape = DebugLaunch.planShape { exploreShape = shape }
            if let routes = DebugLaunch.planRoutes { exploreRouteCount = routes }
            if let minimum = DebugLaunch.planMinimumNew { exploreMinimumNew = minimum }
            if !DebugLaunch.skipLocation { location.start() }
            if let pin = droppedPin { describePin(at: pin) }
            if DebugLaunch.planAutoRun { await autoPlan() }
            if DebugLaunch.hideCard {
                try? await Task.sleep(for: .seconds(12))
                parkCard()
                try? await Task.sleep(for: .seconds(8))
                showCard()
            }
        }
        .task(id: reloadKey) { await reload() }
        // The explorer's index covers every workout, so it is rebuilt when the workout set
        // changes rather than when the map's range does.
        .task(id: health.workouts.count) { coverage.update(workouts: health.workouts) }
        // The screen's menus are drawn in the map screen itself (`menuPanel`), not presented as
        // sheets: see `View.glassPanel()` for what a half-height sheet's card does to the Duo's
        // rail. The export preview is the one cover: a full-screen viewer for the image it
        // produces rather than a panel over the map.
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
        visibleMapRect ?? RouteGeometry.fittedRect(routes: loaded.map { $0.1.coordinates })
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

    /// The distance from the screen's bottom edge to the bottom edge of the overlays that keep to it
    /// — the filter column, and the menu panels, which sit where the filters do.
    private var overlayBottomInset: CGFloat {
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

    /// How far the explorer's card is held off the screen edges: at least the inset the other
    /// overlays keep, and further wherever the window reserves a rail or a cut-out — the card is
    /// full width, so unlike the filter column it cannot simply keep to the side the rail is not
    /// on, and its own close button ended up under the rail.
    private var cardLeadingInset: CGFloat { max(Metrics.screenInset, windowInsets.left) }
    private var cardTrailingInset: CGFloat { max(Metrics.screenInset, windowInsets.right) }

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
                         planned: plannedLines,
                         pin: droppedPin,
                         pinTitle: pinPlace?.title ?? "Dropped pin",
                         pinSubtitle: pinPlace?.subtitle ?? "",
                         onPinDelete: { clearPin() },
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
                         onLongPress: { dropPin(at: $0) },
                         onPlannedTap: { select(route: $0) },
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

                // The explorer's card sits under the bubble rather than at the foot of the
                // screen: the foot is where the filters and the toolbar live, and both have to
                // stay usable while a route is planned.
                if isPlanning {
                    planningBubble
                        .padding(.top, 10)
                } else if let plan {
                    PlannedRouteBar(plan: plan,
                                    selected: $selectedRoute,
                                    isActive: planActive,
                                    isLight: controlsAreLight,
                                    onGo: { planActive = true },
                                    onClear: { clearPlan() })
                        .environment(\.colorScheme, controlsAreLight ? .light : .dark)
                        .padding(.leading, cardLeadingInset)
                        .padding(.trailing, cardTrailingInset)
                        .padding(.top, 10)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            // The card sits below the range bubble, so it has to travel its own
                            // height plus that gap to be clear of the top of the screen.
                            cardTravel = height + 90
                        }
                        .offset(y: cardOffset)
                        .gesture(cardDrag)
                        // Off the top of the screen it is still laid out, so it must not keep
                        // taking taps.
                        .allowsHitTesting(!cardParked)
                }

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    if filtersOnTrailingEdge { Spacer(minLength: 0) }
                    categoryFilters
                        .environment(\.colorScheme, controlsAreLight ? .light : .dark)
                        .id(controlsAreLight)
                    if !filtersOnTrailingEdge { Spacer(minLength: 0) }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, overlayBottomInset)
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

            // The explorer's input, the calendar and the map-style picker, as the screen's own
            // panels — above the controls, the way the sheets they used to be sat above them.
            if showPlanner {
                menuPanel { room in
                    RoutePlannerPanel(mode: $planMode,
                                      kilometers: $planKilometers,
                                      destination: $planDestination,
                                      droppedPin: droppedPin,
                                      region: currentRegion,
                                      isReadingRoutes: coverage.isFilling,
                                      room: room,
                                      onClose: { showPlanner = false },
                                      onPlan: { request in
                                          showPlanner = false
                                          startPlanning(request)
                                      })
                }
            }
            if showRange {
                menuPanel { room in
                    RangePickerPanel(selection: $selection,
                                     workouts: health.workouts,
                                     room: room,
                                     onClose: { showRange = false })
                }
            }
            if showModes {
                menuPanel { room in
                    MapModePanel(mode: $mapMode,
                                 appearance: mapAppearance,
                                 systemStyle: systemAppearance.style,
                                 room: room,
                                 onClose: { showModes = false })
                }
            }
        }
    }

    /// Where a menu panel of the map screen sits: the width the range bubble and the result card
    /// keep, so the panel reaches the rail the Duo's toolbar and tab registers live in without
    /// touching it, and clear of the tab bar's own top edge.
    ///
    /// The panel is handed the room it has to work with rather than a height of its own, so a
    /// keyboard — which pushes the panel up but cannot make the screen taller — cannot take its
    /// header and its close cross off the top. The container's own safe area is ignored (the panel
    /// measures itself from the screen's edges, like the card does, instead of from the region left
    /// over beside the rail); the keyboard's inset is what does the pushing, and it has to keep
    /// doing it.
    private func menuPanel<Content: View>(@ViewBuilder _ content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { proxy in
            content(proxy.size.height - overlayBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.leading, cardLeadingInset)
                .padding(.trailing, cardTrailingInset)
                .padding(.bottom, overlayBottomInset)
        }
        .ignoresSafeArea(.container)
    }

    /// Walk / Run / Ride as toolbar circles — symbol only, walk at the top, the selected
    /// one carrying its own colour. They sit opposite the toolbar.
    ///
    /// The explorer stands above them with twice the gap between the three, so it reads as a
    /// group of its own. It is **independent** of the three: it neither selects nor deselects
    /// one, and a walk filter can be on while an explorer route is on the map.
    private var categoryFilters: some View {
        VStack(spacing: Metrics.pillGap) {
            exploreButton
                .padding(.bottom, Metrics.pillGap)
            ForEach(WorkoutCategory.allCases) { item in
                filterButton(item)
            }
        }
    }

    /// The explorer's button: binoculars, its own blue while it is on, the same glass circle as
    /// the filters otherwise.
    ///
    /// It opens the input sheet when there is nothing planned, brings the result card back down
    /// when that has been swiped away, and opens the sheet again when the card is already up —
    /// so the route can be stopped and another one started from anywhere.
    private var exploreButton: some View {
        Button {
            if (plan != nil || isPlanning) && cardParked {
                showCard()
            } else {
                showPlanner = true
            }
        } label: {
            toolbarGlyph("binoculars.fill", tint: exploreIsOn ? RouteBlue.primary : controlGlyph)
        }
        .buttonStyle(.plain)
        .glassEffect(exploreIsOn ? .regular.tint(RouteBlue.primary.opacity(0.25)) : .regular,
                     in: .circle)
        .accessibilityLabel("Explore")
    }

    private func filterButton(_ item: WorkoutCategory) -> some View {
        let selected = category == item
        return Button {
            toggle(item)
        } label: {
            toolbarGlyph(item.symbolName, tint: selected ? modeColors.color(for: item) : controlGlyph)
        }
        .buttonStyle(.plain)
        // A light wash behind the symbol; if the glass ignores the alpha the symbol alone
        // carries the colour.
        .glassEffect(selected ? .regular.tint(modeColors.color(for: item).opacity(0.25)) : .regular,
                     in: .circle)
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
                    if kind != .all { showRange = true }
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
            // The same frosted glass as the explorer's own card, so the map shows through the
            // pill rather than sitting under a grey plate.
            .background(.regularMaterial, in: Capsule())
            .environment(\.colorScheme, controlsAreLight ? .light : .dark)
    }

    /// What the screen shows while a route is being planned: `MKDirections` answers in about a
    /// second per leg, and a plan is a handful of them.
    private var planningBubble: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(controlGlyph)
            Text("Finding new ways\u{2026}")
                .font(.system(size: 14))
                .foregroundStyle(controlsAreLight ? Palette.rangeLabelLight : Palette.rangeLabel)
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.controlHeight)
        .background(.regularMaterial, in: Capsule())
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
            if kind != .all { showRange = true }
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

    // MARK: - Explorer

    /// Dragging the result card up puts it away without touching the route.
    ///
    /// The card tracks the finger the whole way, and the release only decides which end it
    /// settles at: past a third of the way off, or flicked fast enough that it *would* have got
    /// there, it leaves; otherwise it springs back. The animation is a spring so the flick lands
    /// with some weight instead of stopping dead.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                cardOffset = cardOffset(for: value.translation.height)
            }
            .onEnded { value in
                let projected = min(value.translation.height, value.predictedEndTranslation.height)
                let leaves = projected < -cardTravel / 3
                cardParked = leaves
                // A bouncier spring than a plain ease: the snap-back is the part that has to
                // feel like a piece of iOS, and it overshoots a little on the way home.
                withAnimation(.spring(response: 0.36, dampingFraction: leaves ? 0.9 : 0.76)) {
                    cardOffset = leaves ? -cardTravel : 0
                }
            }
    }

    /// The card's offset for a pull of the finger: one to one while there is somewhere to go,
    /// and past that the rubber band iOS puts on a drag that has run out of room — the pull
    /// still moves it, by less and less, so the edge gives instead of stopping dead. Dragging
    /// *down* is all rubber band, because there is nothing below the resting place at all.
    private func cardOffset(for pull: CGFloat) -> CGFloat {
        guard pull < 0 else { return rubberBand(pull, limit: cardTravel * 0.20) }
        let travelled = min(-pull, cardTravel)
        let past = max(0, -pull - cardTravel)
        return -travelled - rubberBand(past, limit: cardTravel * 0.20)
    }

    /// `UIScrollView`'s own rubber band: the displacement approaches `limit` as the pull grows,
    /// and a small pull moves it about half as far as the finger.
    private func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard distance > 0, limit > 0 else { return 0 }
        let constant: CGFloat = 0.55
        return (distance * limit * constant) / (limit + constant * distance)
    }

    /// Brings the result card back down from wherever it is parked.
    private func showCard() {
        cardParked = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.74)) { cardOffset = 0 }
    }

    /// Puts it away again — the debug hook and the flicked-away state share this.
    private func parkCard() {
        cardParked = true
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { cardOffset = -cardTravel }
    }

    /// Picking one of the planned routes by tapping it on the map — the same choice the pills on
    /// the card make.
    private func select(route index: Int) {
        guard let plan, plan.routes.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { selectedRoute = index }
    }

    /// Plans a route for the request the sheet handed over, and fits the map to the result.
    ///
    /// The planner is given the coverage index for **all** workouts, so "new ways" means new to
    /// the user and not just new to the range the map happens to be showing.
    private func startPlanning(_ request: PlanRequest) {
        planTask?.cancel()
        guard let start = planStart else { return }
        isPlanning = true
        planActive = false
        plan = nil
        selectedRoute = 0
        cardParked = false
        cardOffset = 0
#if DEBUG
        let client: DirectionsClient = DebugLaunch.fakePlan
            ? FixtureDirectionsClient()
            : MapKitDirectionsClient()
#else
        let client: DirectionsClient = MapKitDirectionsClient()
#endif
        planTask = Task { @MainActor in
            let index = await coverage.index(for: health.workouts)
            var planner = RoutePlanner()
            planner.strategy = DebugLaunch.planAlgorithm ?? .tour
            planner.routeCount = exploreRouteCount
            planner.shape = exploreShape
            planner.minimumNew = exploreMinimumNew
            let result = await planner.plan(request: request, start: start,
                                            coverage: index, client: client)
            guard !Task.isCancelled else { return }
            isPlanning = false
            plan = result
            selectedRoute = 0
            if DebugLaunch.planAutoGo, result != nil { planActive = true }
            if let rect = RouteGeometry.fittedRect(routes: result?.routes.map(\.coordinates) ?? []) {
                camera = .fit(rect)
                cameraToken += 1
            }
        }
    }

    /// Clears the planned route: it leaves the map and the explorer's button goes back to its
    /// default look.
    private func clearPlan() {
        planTask?.cancel()
        isPlanning = false
        planActive = false
        plan = nil
        selectedRoute = 0
    }

    /// Drops — or moves — the destination pin, as a long press on the map does in Maps. One pin
    /// at a time, and a destination that *was* the pin follows it.
    ///
    /// The address is geocoded for the pin's info bubble; it arrives a moment after the pin
    /// itself, so the pin shows the coordinate until it does.
    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        droppedPin = coordinate
        pinPlace = nil
        if planDestination?.isPin == true {
            planDestination = PlanDestination(coordinate: coordinate, name: "Pin on the map", isPin: true)
        }
        describePin(at: coordinate)
    }

    /// The bin in the pin's info bubble: the pin leaves the map, and a destination that was the
    /// pin goes with it.
    private func clearPin() {
        droppedPin = nil
        pinPlace = nil
        if planDestination?.isPin == true { planDestination = nil }
    }

    private func describePin(at coordinate: CLLocationCoordinate2D) {
        Task { @MainActor in
            let place = await PinPlace.describe(coordinate)
            // The pin may have been dropped somewhere else, or removed, in the meantime.
            guard let droppedPin, Geo.same(droppedPin, coordinate) else { return }
            pinPlace = place
        }
    }

    /// `WM_PLAN_AUTORUN=1`: waits for a fix and plans straight away, so the whole path can be
    /// exercised from the command line without touching the sheet.
    private func autoPlan() async {
        if planMode == .destination, let pin = droppedPin {
            planDestination = PlanDestination(coordinate: pin, name: "Pin on the map", isPin: true)
        }
        try? await Task.sleep(for: .seconds(3))
        let request = PlanRequest(mode: planMode,
                                  targetMeters: planKilometers * 1000,
                                  destination: planMode == .destination ? planDestination?.coordinate : nil,
                                  destinationName: planMode == .destination ? planDestination?.name : nil)
        startPlanning(request)
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
        if let rect = RouteGeometry.fittedRect(routes: loaded.map { $0.1.coordinates }) {
            // The debug hook holds the camera at a fixed span over the same routes, so the
            // overlay can be looked at at one zoom level at a time (`WM_ZOOM_SPAN`).
            if let span = DebugLaunch.zoomSpan {
                camera = .center(MKMapPoint(x: rect.midX, y: rect.midY).coordinate, spanMeters: span)
            } else {
                camera = .fit(rect)
            }
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

        await withTaskGroup(of: (Workout, WorkoutRoute).self) { group in
            for workout in missing {
                group.addTask { (workout, await RouteStore.shared.route(for: workout.hk)) }
            }
            // Applying every arrival on its own re-tessellates all the routes already
            // on screen once per arrival — that is what made the Year and All ranges
            // crawl while they loaded. They are applied in batches instead.
            var arrived: [(Workout, WorkoutRoute)] = []
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

    private func merge(_ batch: [(Workout, WorkoutRoute)]) {
        let ids = Set(batch.map { $0.0.id })
        loaded.removeAll { ids.contains($0.0.id) }
        loaded.append(contentsOf: batch)
    }
}

