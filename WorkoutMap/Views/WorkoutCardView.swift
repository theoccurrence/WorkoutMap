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
    /// The tone each jump rule draws in — the same choice the map screen uses.
    @ObservedObject private var jumpColors = JumpColorStore.shared
    /// What the user changed about the route in the editor — erased ground, or a jump flagged as
    /// ground they covered. The thumbnail is drawn with those edits, and the row carries a badge
    /// while there are any.
    @ObservedObject private var editStore = RouteEditStore.shared

    private var thumbnailWidth: CGFloat { Metrics.thumbnailWidth }

    private var edits: RouteEdits { editStore.edits(for: workout.id) }

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
                HStack(spacing: 6) {
                    Text(workout.listDateText)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                    if !edits.isEmpty { editedBadge }
                }
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

    /// A small mark that this workout's route has been edited in the app. The list is where a
    /// workout is picked, so it is where the user should be able to see that one of them carries
    /// an edit before opening it.
    private var editedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eraser.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Edited")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(Palette.accent.opacity(0.16), in: Capsule())
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
                                                              tones: jumpColors.tones,
                                                              edits: edits,
                                                              size: target,
                                                              scale: displayScale) {
            withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
        }
    }

    /// What the thumbnail is drawn from: the card's own size, the jump rules, the tone they draw
    /// in, the mode's colour and the legs the user erased, so a change to any of them draws it
    /// again.
    private var loadKey: String {
        "\(size.width)x\(size.height)-\(jumpRules.key)-\(jumpColors.tones.key)-\(modeColors.hexString(for: workout.category))-\(edits.key)"
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
