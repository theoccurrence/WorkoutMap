import SwiftUI
import MapKit
import CoreLocation

/// The two things the route editor's brush can do.
enum EditTool: String, CaseIterable, Identifiable {
    /// Take ground out of the line.
    case eraser
    /// Flag a leg the GPS-jump rules caught as ground the user really covered.
    case valid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eraser: return "Eraser"
        case .valid: return "Jump valid"
        }
    }

    var symbolName: String {
        switch self {
        case .eraser: return "eraser"
        case .valid: return "checkmark.circle"
        }
    }
}

/// The route-editing screen: the workout's route on the map, with a brush on it.
///
/// Nothing about the workout changes — Health's data cannot be changed, by this app or by the
/// Fitness app — and what the brush changes is how the workout's route is *drawn*: the legs it
/// passes over are kept (in `RouteEditStore`) as ranges of the route's own leg indices, and every
/// screen that draws the route draws it that way from then on, without asking Health again.
///
/// The brush has two tools, because there are two things to say about a leg. **Eraser** takes it out
/// of the line. **Jump valid** says the opposite for a leg a GPS-jump rule caught: the ground was
/// covered, so the rules must leave it alone — the map and the list draw it as an ordinary part of
/// the route — while this screen and the workout's detail screen still draw it as the jump it is, in
/// the route's own colour dotted, so the flag can be seen and taken back.
///
/// Working in **legs**, rather than in fixes or in a trimmed copy of the track, is the whole of why
/// this works on the jump lines as well: a dotted jump line *is* one leg, so erasing it — or flagging
/// it — is naming one index, and because the drawing only ever emits the legs it is given and never
/// invents one between two fixes an erasure separated, taking a stretch out of the route cannot leave
/// a phantom line across the gap.
struct WorkoutEditView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RouteEditStore.shared
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    @ObservedObject private var modeColors = CategoryColorStore.shared
    @ObservedObject private var jumpColors = JumpColorStore.shared
    /// Whether Satellite draws its labels layer — the same setting the map screen's panel writes.
    @AppStorage(MapMode.satelliteLabelsKey) private var satelliteLabels = true

    @State private var route = WorkoutRoute(coordinates: [])
    /// The edit being made. Seeded from the store when the screen opens and written back only on
    /// *Done*, so leaving without saving changes nothing.
    @State private var edits = RouteEdits.empty
    /// The edit as it was before each stroke, so Undo steps back a stroke at a time.
    @State private var history: [RouteEdits] = []
    /// Whether the stroke in progress has already put its "before" on the history — one entry per
    /// stroke, not one per touch event.
    @State private var strokeOpen = false
    @State private var tool: EditTool = EditTool(rawValue: DebugLaunch.startEditTool ?? "") ?? .eraser
    @State private var brush: Double = 34
    @State private var cursor: CGPoint?
    /// Whether the tools panel has been swiped away. While it is, the screen carries the chevron
    /// that brings it back at the display's bottom trailing corner — the one control the panel cannot
    /// carry, because the panel is what is away (`restoreTools`).
    @State private var toolsHidden = DebugLaunch.editToolsHidden

    /// How the map is drawn — the same settings the other map screens read.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance = .system
    @AppStorage(JumpSettings.distanceStyleKey) private var jumpDistanceStyle: RouteJumpStyle = JumpRules.standard.distanceStyle
    @AppStorage(JumpSettings.distanceThresholdKey) private var jumpDistanceThreshold: Double = JumpRules.standard.distanceThreshold
    @AppStorage(JumpSettings.speedStyleKey) private var jumpSpeedStyle: RouteJumpStyle = JumpRules.standard.speedStyle
    @AppStorage(JumpSettings.speedThresholdKey) private var jumpSpeedThreshold: Double = JumpRules.standard.speedThreshold

    /// How far the brush reaches, in points on the screen.
    private static let brushRange: ClosedRange<Double> = 12...70

    private var jumpRules: JumpRules {
        JumpRules(distanceStyle: jumpDistanceStyle,
                  distanceThreshold: jumpDistanceThreshold,
                  speedStyle: jumpSpeedStyle,
                  speedThreshold: jumpSpeedThreshold)
    }

    private var mapInterfaceStyle: UIUserInterfaceStyle {
        mapAppearance.interfaceStyle(for: MapMode.stored, system: systemAppearance.style)
    }

    private var routeColor: UIColor { modeColors.uiColor(for: workout.category) }

    /// The route as this screen draws it: the erased legs out, and the flagged ones still shown as
    /// the jumps they are — this is the screen whose business the flag is.
    private var lines: [MapRouteLine] {
        MapRouteLine.lines(for: workout,
                           route: route,
                           rules: jumpRules,
                           color: routeColor,
                           tones: jumpColors.tones,
                           edits: edits,
                           showValidatedJumps: true)
    }

    private var visible: [CLLocationCoordinate2D] { route.visible(edits) }

    /// What the brush is drawn in: the eraser is the white ring the finger reads as a rubber, and
    /// the valid brush takes the route's own colour — the same colour the leg it flags is drawn in.
    private var brushTint: Color {
        tool == .eraser ? .white : Color(routeColor)
    }

    var body: some View {
        GeometryReader { proxy in
            // The display, which is what the cards are placed against: `menuCard` resolves a card's
            // corner from where the card sits *on the display*, and this screen's reader is inside the
            // safe area, so its size is the display less the bands the system reserves.
            let display = CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                                 height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                RouteMapView(routes: lines,
                             camera: RouteGeometry.fittedRect(routes: [visible]).map { .fit($0) },
                             cameraToken: route.count,
                             mode: MapMode.stored,
                             satelliteLabels: satelliteLabels,
                             interfaceStyle: mapInterfaceStyle,
                             brushRadius: CGFloat(brush),
                             onEditStroke: applyStroke(from:to:radius:),
                             onBrushCursor: { point in
                                 cursor = point
                                 if point == nil { strokeOpen = false }
                             })
                    .ignoresSafeArea()

                brushCircle

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                }

                // The tools, as one of the app's own cards — the same shape every other floating panel
                // of the app has (`menuCard`), the same margin from the display's edges
                // (`menuCardInsets`), and the swipe that puts it away. It is laid out against the
                // **display's** bottom edge rather than the safe area's, which is where the map
                // screen's own cards sit.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !toolsHidden {
                        toolsPanel
                            .menuCard(display: display, onDismiss: { setTools(hidden: true) })
                            .menuCardInsets()
                            // It rises out of the display's bottom edge and goes back down through
                            // it, the way the map screen's menus do.
                            .transition(.move(edge: .bottom))
                    }
                }
                .ignoresSafeArea(.container)

                // The way back, in its own layer so it never takes room from the panel.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        restoreTools
                    }
                    .padding(.trailing, Metrics.screenInset)
                    .padding(.bottom, Metrics.screenInset)
                }
                .ignoresSafeArea(.container)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: workout.id) { await load() }
        .statusBarHidden()
    }

    /// The chevron that brings the tools back, shown only while they are away.
    ///
    /// It fades in as the panel leaves and out as the panel returns, on the panel's own spring — the
    /// same fade the map screen's own toolbar and filter circles run while one of its menus is up
    /// (`menuControlsHidden`), so a control that belongs to a card comes and goes the way the rest of
    /// the app's do. `allowsHitTesting` is what keeps an invisible button from taking taps, as it is
    /// there: a SwiftUI view at opacity 0 is still hit-testable.
    private var restoreTools: some View {
        GlassCircleButton(symbol: "chevron.up", label: "Show tools") {
            setTools(hidden: false)
        }
        .opacity(toolsHidden ? 1 : 0)
        .allowsHitTesting(toolsHidden)
    }

    /// Puts the tools panel away, or brings it back: both on the app's own card spring (`MenuMotion`),
    /// which is what the chevron fades on as well, so the card and the control that stands for it move
    /// as one thing.
    private func setTools(hidden: Bool) {
        withAnimation(MenuMotion.animation) { toolsHidden = hidden }
    }

    // MARK: - chrome

    /// The screen's two actions, at the display's own top corners: the close cross and *Done*.
    ///
    /// Both are the system's own glass buttons (`GlassCircleButton` — `.buttonStyle(.glass)`), which is
    /// what makes them react to a touch the way the map screen's rail does; they are drawn into the
    /// screen rather than declared as toolbar items, and that is measured: a `NavigationStack` bar with
    /// items in it **insets** the screen (the map stopped being full bleed and started ~103 pt down, at
    /// the bar's own edge), while the bar of a screen with no items in it — as on the map screen — costs
    /// nothing. A full-bleed map is worth more here than a system-placed button.
    private var topBar: some View {
        ZStack {
            Text("Edit Route")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                MenuCloseButton { dismiss() }
                Spacer(minLength: 8)
                doneButton
            }
        }
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 8)
        .frame(height: 52)
    }

    /// *Done*: the screen's confirm, on the same glass as everything else and in the accent colour,
    /// the way the map screen's own toolbar carries its selected action. Its size is the system's, but
    /// its label sits in the same **fixed box** (`Metrics.glassButtonLabel`) the round buttons use, so a
    /// capsule — which the system pads 15 pt a side just like a circle — comes out at the same 48.5 pt
    /// as the close cross beside it instead of the 50.3 the bare text line would give it.
    private var doneButton: some View {
        Button(action: save) {
            Text("Done")
                .fontWeight(.semibold)
                .frame(height: Metrics.glassButtonLabel)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Palette.accent)
        .accessibilityLabel("Done")
    }

    private var toolsPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(EditTool.allCases) { option in
                    toolButton(option)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 24)
                Slider(value: $brush, in: Self.brushRange)
                    .tint(Palette.accent)
                    .accessibilityLabel("Brush size")
                Text("\(Int(brush))")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 30, alignment: .trailing)
            }

            HStack(spacing: 10) {
                actionButton(title: "Undo",
                             systemImage: "arrow.uturn.backward",
                             enabled: !history.isEmpty,
                             action: undo)
                actionButton(title: "Clear",
                             systemImage: "trash",
                             enabled: !edits.isEmpty,
                             action: clearAll)
            }

            Text("Drag over the route with the brush. Two fingers move the map, a pinch zooms. The workout in Health is not changed.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    /// One tool: its glyph and name, in the accent colour while it is the one the brush uses.
    private func toolButton(_ option: EditTool) -> some View {
        let selected = option == tool
        return Button {
            tool = option
        } label: {
            HStack(spacing: 7) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(selected ? Palette.accent : Palette.surface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The brush, drawn under the finger so its size can be seen before it is used.
    @ViewBuilder
    private var brushCircle: some View {
        if let cursor {
            Circle()
                .fill(brushTint.opacity(0.12))
                .overlay(Circle().stroke(brushTint.opacity(0.9), lineWidth: 1.5))
                .frame(width: brush, height: brush)
                .position(x: cursor.x, y: cursor.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func actionButton(title: String,
                              systemImage: String,
                              enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    // MARK: - actions

    private func load() async {
        route = RouteStore.shared.cached(workout.id) ?? WorkoutRoute(coordinates: [])
        edits = store.edits(for: workout.id)
        history = []
        let full = await RouteStore.shared.route(for: workout.hk)
        if !full.isEmpty { route = full }
#if DEBUG
        // WM_EDIT_SAVE=1 — see `DebugLaunch.editSave`. The simulator cannot tap *Done* from the
        // command line, so the edit is written through the very call Done makes, once the
        // `WM_EDIT_STROKE` stroke has had time to land.
        if DebugLaunch.editSave {
            try? await Task.sleep(for: .seconds(DebugLaunch.editStrokeDelay + 2))
            save()
        }
        // WM_EDIT_TOOLS=<seconds> — see `DebugLaunch.editToolsCycle`.
        if let after = DebugLaunch.editToolsCycle {
            try? await Task.sleep(for: .seconds(after))
            setTools(hidden: true)
            try? await Task.sleep(for: .seconds(after))
            setTools(hidden: false)
        }
#endif
    }

    private func save() {
        store.set(edits, for: workout.id)
        dismiss()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        edits = previous
    }

    /// Puts everything back: both tools' work, since the button says *Clear* and not *Clear erased*.
    private func clearAll() {
        guard !edits.isEmpty else { return }
        history.append(edits)
        edits = .empty
    }

    /// Takes the stroke's legs and hands them to the tool in use.
    private func applyStroke(from previous: MKMapPoint?, to current: MKMapPoint, radius: Double) {
        let reached = legs(in: previous, to: current, radius: radius)
        guard !reached.isEmpty else { return }
        // One undo step per stroke, not per touch event — and none for a stroke that hit nothing.
        if !strokeOpen {
            history.append(edits)
            strokeOpen = true
        }
        edits = tool == .eraser ? edits.erasing(reached) : edits.validating(reached)
    }

    /// The legs the brush reached.
    ///
    /// The stroke is walked in steps small enough that no ground passes between two of them unnoticed:
    /// a jump leg can be hundreds of metres long, and a stroke across its middle has to catch it
    /// without the finger ever touching either end. Each sample is measured against each leg with the
    /// same point-to-segment test the map's own tap hit-test uses.
    ///
    /// Which legs are candidates is the tool's business. The eraser may take any leg it reaches. The
    /// valid brush may only flag what a rule actually caught — an ordinary leg is already drawn as
    /// walked, so flagging it would say nothing, and a leg the strict rule owns is the receiver's
    /// invention, so drawing a line across it would be a lie.
    private func legs(in previous: MKMapPoint?,
                      to current: MKMapPoint,
                      radius: Double) -> IndexSet {
        guard radius > 0, route.count > 1 else { return [] }
        let limit = radius * radius
        let step = max(radius / 2, 1)

        var samples: [MKMapPoint] = []
        if let previous {
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            let steps = max(1, Int(((dx * dx + dy * dy).squareRoot() / step).rounded(.up)))
            samples.reserveCapacity(steps + 1)
            for index in 0...steps {
                let t = Double(index) / Double(steps)
                samples.append(MKMapPoint(x: previous.x + dx * t, y: previous.y + dy * t))
            }
        } else {
            samples = [current]
        }

        let rules = jumpRules
        var hit = IndexSet()
        for leg in 1..<route.count {
            switch tool {
            case .eraser:
                guard !edits.erased.contains(leg) else { continue }
            case .valid:
                guard !edits.validated.contains(leg),
                      route.jumpKind(leg, rules: rules) != nil else { continue }
            }
            let a = MKMapPoint(route.coordinates[leg - 1])
            let b = MKMapPoint(route.coordinates[leg])
            for sample in samples where Geo.pointToSegmentSquared(sample, a, b) <= limit {
                hit.insert(leg)
                break
            }
        }
        return hit
    }
}
