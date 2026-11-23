import SwiftUI
import MapKit
import CoreLocation

struct WorkoutDetailView: View {
    let workout: Workout
    /// How the screen was opened. `pushed` fills the window edge to edge: the Workouts tab pushes it
    /// inside its own navigation stack, and the README says why that one keeps the Duo's rail band
    /// empty rather than drawing a card in it. `sheet` is the same screen inside a sheet's card — the
    /// map's range bubble and the settings' edited list — where the card's own top and side margins
    /// are the system's and the **bottom** one is drawn here: the black backdrop ends above the
    /// display's bottom edge with the same margin as the other three sides, so those four sides read
    /// as one card, and the card's corners follow the display's the way the sheet's do.
    enum Presentation { case pushed, sheet }
    let presentation: Presentation

    @Environment(\.dismiss) private var dismiss
    @State private var route = WorkoutRoute(coordinates: [])
    @State private var showExport = DebugLaunch.openExport
    /// The route-editing screen. Its edits are the app's own — the workout itself is untouched.
    @State private var showEdit = DebugLaunch.startEdit
    @State private var visibleMapRect: MKMapRect?
    /// How the map is drawn, matching the map screen: the appearance setting against the
    /// system's own style.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance = .system
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
            // The card this screen was given, safe areas included: the content runs to the card's own
            // edges, and the margins *it* keeps are the sheet's, not this screen's to invent.
            let full = CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                              height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            // How far the sheet's own card is held off the display's leading edge. A card the system
            // has already inset (measured: 8 pt on the Duo's folded panel, on all three of its other
            // sides with it) keeps that margin, and one it has not (measured: 0 pt on the iPhone 18
            // Pro Max, whose sheet card is the full width of the display) is given the same margin the
            // map screen's menu cards keep — so the two cards are the same card on either display.
            // The bottom is the one side the system's card does not inset, which is why the backdrop
            // used to run off the display there: it is inset here either way.
            let cardInset = max(0, proxy.frame(in: .global).minX - proxy.safeAreaInsets.leading)
            let sideInset = presentation == .sheet ? max(0, Metrics.menuCardInset - cardInset) : 0
            let bottomInset = presentation == .sheet ? Metrics.menuCardInset : 0
            VStack(spacing: 0) {
                // The map takes what the stats and the source label leave rather than a fixed share of
                // the screen: the reference display gave it 59.96 % (measured), and it gets that
                // whenever the block below it is the size the reference had — but a smaller screen, or
                // a wider one that lays the same six cards out in fewer rows, can never leave a card
                // or the `*Data from …` label outside the card for want of the space.
                mapSection
                stats(landscape: full.width > full.height)
                    .padding(.horizontal, 23)
                    .padding(.top, 18)
                footer
                    .padding(.horizontal, 23)
                    .padding(.top, 17)
            }
            .frame(width: full.width - 2 * sideInset,
                   height: full.height - bottomInset,
                   alignment: .top)
            // The black backdrop, shaped: pushed it is the display's own rectangle (nothing is clipped
            // that the display does not clip anyway), and inside a sheet it is the card the sheet's own
            // card is — the display's corners, its bottom two included, which the system's card does
            // not round on a card that runs off the bottom of the display.
            .background(Color.black, in: cardShape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Edge to edge, the way the map screen draws. Laid out inside the safe area, this
            // screen left the strip the system reserves for its own rail (the Duo's vertical bar
            // on the screen's side, in every pose but the unfolded portrait) as a band of empty
            // black with nothing in it, and the map stopped short of it too. Nothing here lives
            // in that rail — the back and share buttons are placed on the reader above, still
            // clear of it — so the whole screen belongs to the screen.
            .ignoresSafeArea()
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { topTrailingButtons }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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

    /// The shape of that card. Pushed, it is the display's own rectangle, and a clip on one would cost
    /// the map a mask for nothing. Inside a sheet it is the shape the sheet's own card is — the
    /// display's corners, inset by the card's margin (`View.menuCard()`) — so the bottom two corners
    /// are as round as the top two.
    private var cardShape: AnyShape {
        presentation == .sheet
            ? AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.menuCardRadius))))
            : AnyShape(Rectangle())
    }

    /// The map, as tall as the rest of the screen leaves it. Nothing is clipped off the stats or the
    /// source label to make room for it: they are laid out at their own size and the map is what
    /// gives.
    private var mapSection: some View {
        RouteMapView(routes: lines,
                     camera: RouteGeometry.fittedRect(routes: [visibleCoordinates]).map { .fit($0) },
                     cameraToken: route.count,
                     mode: MapMode.stored,
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

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }

    /// The two actions the screen's top trailing corner carries: the route editor, and the export
    /// card.
    private var topTrailingButtons: some View {
        HStack(spacing: 0) {
            editButton
            shareButton
        }
        .padding(.trailing, 8)
    }

    /// Opens the route editor: the eraser the screen is named for. Health's workout is not touched
    /// by it — what is edited is how this app draws the workout's route.
    private var editButton: some View {
        Button { showEdit = true } label: {
            Image(systemName: "eraser")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit route")
    }

    private var shareButton: some View {
        Button { showExport = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
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
