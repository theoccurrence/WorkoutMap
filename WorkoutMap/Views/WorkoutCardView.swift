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
    /// What the map does with a GPS jump — the same setting the map screen reads.
    @AppStorage(RouteJumpStyle.storedKey) private var jumpStyle: RouteJumpStyle = .dotted
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
                                                              style: jumpStyle,
                                                              size: target,
                                                              scale: displayScale) {
            withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
        }
    }

    /// What the thumbnail is drawn from: the card's own size and the jump setting, so a change to
    /// either draws it again.
    private var loadKey: String {
        "\(size.width)x\(size.height)-\(jumpStyle.rawValue)-\(modeColors.hexString(for: workout.category))"
    }

    private func route() async -> WorkoutRoute {
        if let cached = RouteStore.shared.cached(workout.id) { return cached }
        return await RouteStore.shared.route(for: workout.hk)
    }
}
