import SwiftUI
import MapKit
import CoreLocation

/// The route-editing screen: the workout's route on the map, with an eraser on it.
///
/// Nothing about the workout changes — Health's data cannot be changed, by this app or by the
/// Fitness app — and what the eraser takes out is how the workout's route is *drawn*: the legs the
/// brush passes over are kept (in `EraseStore`) as ranges of the route's own leg indices, and every
/// screen that draws the route draws it without them from then on, without asking Health again.
///
/// Working in **legs**, rather than in fixes or in a trimmed copy of the track, is the whole of why
/// this works on the GPS-jump lines as well: a dotted jump line *is* one leg, so erasing it is
/// erasing one index, and because the drawing only ever emits the legs it is given and never
/// invents one between two fixes an erasure separated, taking a stretch out of the route cannot
/// leave a phantom line across the gap.
struct WorkoutEditView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EraseStore.shared
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    @ObservedObject private var modeColors = CategoryColorStore.shared
    @ObservedObject private var jumpColors = JumpColorStore.shared

    @State private var route = WorkoutRoute(coordinates: [])
    /// The edit being made. Seeded from the store when the screen opens and written back only on
    /// *Done*, so leaving without saving changes nothing.
    @State private var edits = EraseEdits.empty
    /// The edit as it was before each stroke, so Undo steps back a stroke at a time.
    @State private var history: [EraseEdits] = []
    /// Whether the stroke in progress has already put its "before" on the history — one entry per
    /// stroke, not one per touch event.
    @State private var strokeOpen = false
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

    private var lines: [MapRouteLine] {
        MapRouteLine.lines(for: workout,
                           route: route,
                           rules: jumpRules,
                           color: modeColors.uiColor(for: workout.category),
                           tones: jumpColors.tones,
                           erased: edits)
    }

    private var visible: [CLLocationCoordinate2D] { route.visible(erased: edits) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteMapView(routes: lines,
                         camera: RouteGeometry.fittedRect(routes: [visible]).map { .fit($0) },
                         cameraToken: route.count,
                         mode: MapMode.stored,
                         interfaceStyle: mapInterfaceStyle,
                         eraserRadius: CGFloat(brush),
                         onErase: erase(from:to:radius:),
                         onEraseCursor: { point in
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
            Text("Erase Route")
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
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 24)
                Slider(value: $brush, in: Self.brushRange)
                    .tint(Palette.accent)
                    .accessibilityLabel("Eraser size")
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

            Text("Drag over the route to erase it. Two fingers move the map; the workout in Health is not changed.")
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

    /// The brush, drawn under the finger so its size can be seen before it is used.
    @ViewBuilder
    private var brushCircle: some View {
        if let cursor {
            Circle()
                .fill(Color.white.opacity(0.12))
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
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
        // WM_ERASE_SAVE=1 — see `DebugLaunch.eraseSave`. The simulator cannot tap *Done* from the
        // command line, so the edit is written through the very call Done makes, once the
        // `WM_ERASE` stroke has had time to land.
        if DebugLaunch.eraseSave {
            try? await Task.sleep(for: .seconds(DebugLaunch.eraseDelay + 2))
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

    private func clearAll() {
        guard !edits.isEmpty else { return }
        history.append(edits)
        edits = .empty
    }

    /// Takes the legs the brush reached out of the drawing.
    ///
    /// The stroke is walked in steps small enough that no ground passes between two of them
    /// unnoticed: a jump leg can be hundreds of metres long, and a stroke across its middle has to
    /// catch it without the finger ever touching either end. Each sample is measured against each
    /// leg with the same point-to-segment test the map's own tap hit-test uses, and a leg that comes
    /// within the brush's radius is erased — walked legs and jump legs alike.
    private func erase(from previous: MKMapPoint?, to current: MKMapPoint, radius: Double) {
        guard radius > 0, route.count > 1 else { return }
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

        var hit = IndexSet()
        for leg in 1..<route.count where !edits.contains(leg) {
            let a = MKMapPoint(route.coordinates[leg - 1])
            let b = MKMapPoint(route.coordinates[leg])
            for sample in samples where Geo.pointToSegmentSquared(sample, a, b) <= limit {
                hit.insert(leg)
                break
            }
        }
        guard !hit.isEmpty else { return }
        // One undo step per stroke, not per touch event — and none for a stroke that hit nothing.
        if !strokeOpen {
            history.append(edits)
            strokeOpen = true
        }
        edits = edits.erasing(hit)
    }
}
