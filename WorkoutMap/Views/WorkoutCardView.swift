import SwiftUI
import CoreLocation

/// One row in the Workouts list.
///
/// Geometry taken from the original app: the card is 100 pt tall with the icon
/// and text on the left, and a square map thumbnail pinned to the right edge
/// (the last ~100 pt of the card).
struct WorkoutCardView: View {
    @Environment(\.displayScale) private var displayScale
    let workout: Workout

    @State private var thumbnail: UIImage?
    @State private var size: CGSize = .zero
    /// The jump rules — the same settings the map screen reads.
    @AppStorage(JumpSettings.distanceStyleKey) private var jumpDistanceStyle: RouteJumpStyle = JumpRules.standard.distanceStyle
    @AppStorage(JumpSettings.distanceThresholdKey) private var jumpDistanceThreshold: Double = JumpRules.standard.distanceThreshold
    @AppStorage(JumpSettings.speedStyleKey) private var jumpSpeedStyle: RouteJumpStyle = JumpRules.standard.speedStyle
    @AppStorage(JumpSettings.speedThresholdKey) private var jumpSpeedThreshold: Double = JumpRules.standard.speedThreshold
    /// The colour the mode is drawn in — the same choice the map screen uses.
    @ObservedObject private var modeColors = CategoryColorStore.shared

    private var thumbnailWidth: CGFloat { Metrics.thumbnailWidth }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: workout.category.symbolName)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 52)
                .padding(.leading, 25)

            VStack(alignment: .leading, spacing: 8) {
                Text(workout.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(workout.listDateText)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 18)

            Spacer(minLength: 8)

            thumbnailView
                .frame(width: thumbnailWidth, height: Metrics.cardHeight)
        }
        .frame(height: Metrics.cardHeight)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in size = newValue }
            }
        )
        .task(id: loadKey) { await loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailWidth, height: Metrics.cardHeight)
                .clipped()
        } else {
            Palette.card
        }
    }

    private func loadThumbnail() async {
        guard size.width > 1 else { return }
        let route = await route()
        guard route.count > 1 else { return }
        let target = CGSize(width: thumbnailWidth, height: Metrics.cardHeight)
        if let image = await MapImageRenderer.shared.thumbnail(for: workout.id,
                                                              route: route,
                                                              color: modeColors.uiColor(for: workout.category),
                                                              rules: jumpRules,
                                                              size: target,
                                                              scale: displayScale) {
            withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
        }
    }

    /// What the thumbnail is drawn from: the card's own size, the jump rules and the mode's
    /// colour, so a change to any of them draws it again.
    private var loadKey: String {
        "\(size.width)x\(size.height)-\(jumpRules.key)-\(modeColors.hexString(for: workout.category))"
    }

    private var jumpRules: JumpRules {
        JumpRules(distanceStyle: jumpDistanceStyle,
                  distanceThreshold: jumpDistanceThreshold,
                  speedStyle: jumpSpeedStyle,
                  speedThreshold: jumpSpeedThreshold)
    }

    private func route() async -> WorkoutRoute {
        if let cached = RouteStore.shared.cached(workout.id) { return cached }
        return await RouteStore.shared.route(for: workout.hk)
    }
}
