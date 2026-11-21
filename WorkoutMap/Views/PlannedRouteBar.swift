import SwiftUI

/// The explorer's result card: what the planned route is, which of the alternates is the one,
/// and the Go that keeps it on the map.
///
/// Before Go it offers the alternates and a cross that throws the plan away. After Go there is
/// nothing left to pick between — the map shows that one route alone — so the pair becomes a
/// single red **Stop**, and the card can be swiped up out of the way without ending anything:
/// the route stays on the map until Stop, a new plan, or a relaunch.
struct PlannedRouteBar: View {
    let plan: RoutePlan
    @Binding var selected: Int
    /// True once Go was tapped.
    let isActive: Bool
    /// Whether the map is drawn light, so the card follows it the way the range bubble does.
    let isLight: Bool
    var onGo: () -> Void
    var onClear: () -> Void

    private var route: PlannedRoute? {
        plan.routes.indices.contains(selected) ? plan.routes[selected] : plan.routes.first
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distanceText)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(label)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryLabel)
                }
                Spacer(minLength: 0)
                if isActive {
                    // Once the route is the one being walked there is nothing left to pick
                    // between, so the Go and the cross give way to a single red Stop.
                    stopButton
                } else {
                    goButton
                    CloseCircleButton(action: onClear)
                }
            }
            if !isActive, plan.routes.count > 1 {
                selector
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Frosted rather than a flat fill: the map shows through it, but the material is opaque
        // enough that the distance and the share of new ways stay readable over it.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var goButton: some View {
        Button(action: onGo) {
            Text("Go")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)
                .frame(height: 36)
                .background(Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button(action: onClear) {
            Text("Stop")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(Palette.pin, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop the route")
    }

    private var distanceText: String {
        guard let route else { return "—" }
        return Fmt.distance(route.distance)
    }

    private var subtitle: String {
        guard let route else { return "" }
        let percent = Int((route.newFraction * 100).rounded())
        let minutes = Int((route.travelTime / 60).rounded())
        let mode = plan.request.mode == .loop ? "loop" : "to \(plan.request.destinationName ?? "destination")"
        return "\(percent)% new ways · \(minutes) min · \(mode)"
    }

    /// The alternates, as Maps lists them: each one's own distance, the selected one filled in.
    private var selector: some View {
        HStack(spacing: 8) {
            ForEach(Array(plan.routes.enumerated()), id: \.element.id) { index, item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = index }
                } label: {
                    // One decimal and no more: five of these have to share the card's width.
                    Text(Self.pillDistance(item.distance))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(index == selected ? Color.black : label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(index == selected
                                    ? Palette.accent
                                    : Color.white.opacity(isLight ? 0.35 : 0.12),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Route \(index + 1), \(Fmt.distance(item.distance))")
            }
            Spacer(minLength: 0)
        }
    }

    private static func pillDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }

    private var label: Color { isLight ? .black : .white }
    private var secondaryLabel: Color { isLight ? Palette.rangeLabelLight : Palette.textSecondary }
}
