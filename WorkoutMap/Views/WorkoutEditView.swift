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
        ZStack(alignment: .topLeading) {
            RouteMapView(routes: lines,
                         camera: RouteGeometry.fittedRect(routes: [visible]).map { .fit($0) },
                         cameraToken: route.count,
                         mode: MapMode.stored,
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
                tools
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: workout.id) { await load() }
        .statusBarHidden()
    }

    // MARK: - chrome

    private var topBar: some View {
        ZStack {
            Text("Edit Route")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                CloseCircleButton { dismiss() }
                Spacer(minLength: 8)
                Button(action: save) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(height: 30)
                        .padding(.horizontal, 12)
                        .background(Palette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(height: 52)
    }

    private var tools: some View {
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
        .glassPanel()
        .padding(.horizontal, Metrics.contentInset)
        .padding(.bottom, 10)
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
