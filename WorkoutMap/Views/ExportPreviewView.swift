import SwiftUI
import MapKit
import Photos
import CoreLocation

struct ExportPreviewView: View {
    let workout: Workout?
    /// The workouts the card's stats are the **sum** over, when the whole map is being shared: the
    /// ones the map is currently showing, as the filter and the workout-type selection leave them.
    /// Empty for the single-workout export — the detail screen's own share — where `workout` is the
    /// one whose numbers are shown.
    var workouts: [Workout] = []
    let rangeLabel: String
    let mapRect: MKMapRect?
    let routes: [MapRouteLine]
    /// The map style the card is drawn in — the one the map it was exported from shows.
    let mode: MapMode
    /// The style that map is drawn in, so the card matches what the user was looking at.
    let interfaceStyle: UIUserInterfaceStyle

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var containerWidth: CGFloat = 0
    @State private var mapImage: UIImage?
    /// The card, rendered — what the preview shows and what *Save* writes. One image for both, so
    /// the preview cannot promise something the file does not get.
    @State private var preview: UIImage?
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            // The card is rendered at the width the export uses (`cardWidth`): the preview shows the
            // very image *Save* writes, and it is never drawn **bigger** than that image — which is
            // what a plain `.fit` in a frame of the whole window would do on a display wider than the
            // card, at the cost of soft text. A window shorter than the card still scales it down.
            let cardW = cardWidth(proxy.size.width)
            VStack(spacing: 0) {
                // The screen's own close, at the display's trailing edge and inside the room the window
                // reserves there (the Duo's cover panel keeps 84 pt for the system's rail, which is
                // *outside* this reader and so is kept for free). It used to hang 35 pt inside the
                // reader and 3 pt below the display's top edge — the status elements' band on the
                // folded panel, which reports **no** top inset at all, so the cross sat in it.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MenuCloseButton { dismiss() }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, Metrics.screenInset)

                if let preview {
                    // Fitted, never enlarged: a window shorter than the card — the folded panel held
                    // sideways — shows **all** of it instead of the top of its map.
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: cardW, maxHeight: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Spacer(minLength: 0)
                }

                // Inset like every other primary button of the app (`RoutePlannerPanel`,
                // `RangePickerPanel`): full-bleed it was the one control here that touched the
                // window's edges, and in a wide window it read as a bar across the screen.
                PrimaryButton(title: "Save") { Task { await save() } }
                    .padding(.horizontal, Metrics.screenInset)
                    .padding(.bottom, 62)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in containerWidth = width }
        }
        // The status bar goes, as it does on the editor: this is a full-screen viewer for one image on
        // black, and the band it keeps would otherwise be the only thing above the close cross.
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .task(id: previewKey) { await buildPreview() }
        .alert("Saved to Photos", isPresented: $saved) { Button("OK", role: .cancel) {} }
        .alert("Could not save", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    /// What the preview is built from: the card's own width, and whether its map has been rendered yet.
    private var previewKey: String { "\(containerWidth)-\(mapImage == nil)" }

    /// Renders the card the preview shows.
    private func buildPreview() async {
        guard containerWidth > 0 else { return }
        if mapImage == nil { await renderMap() }
        preview = renderCard()
    }

    private func card(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            mapArea(width: width)
                .frame(height: width * 0.78)
            statsGrid
                .padding(.horizontal, 13.4)
                .padding(.top, 15)
            footer
                .padding(.top, 9)
                .padding(.bottom, 9)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(white: 0.41), lineWidth: 1)
        )
        .frame(width: width)
    }

    private func mapArea(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let mapImage {
                    Image(uiImage: mapImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(red: 0.09, green: 0.09, blue: 0.1)
                }
            }
            .frame(width: width)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Map")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text(rangeLabel)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)
            .padding(.bottom, 24)

            HStack(spacing: 4) {
                Image(systemName: "apple.logo").font(.system(size: 11))
                Text("Maps").font(.system(size: 12))
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.leading, 12)
            .padding(.bottom, 7)
        }
        .frame(width: width)
        .clipped()
    }

    /// The four numbers the card carries, as one workout's own or as the sum over the map's set.
    private struct Stats {
        var duration: TimeInterval
        var distance: Double
        var elevation: Double?
        var calories: Double?
    }

    /// What the card's stats are: the sum over the map's own workouts when the whole map is shared,
    /// or the one workout's own numbers otherwise.
    ///
    /// The sum is what the numbers *mean* for a set: time, distance, elevation and active energy all
    /// add up across workouts, so the card says what the whole map adds up to — every walk ever, with
    /// *All* and *Walk* selected, as the user asked. Elevation and calories stay `nil` when no workout
    /// in the set carries them, so the card shows `--` rather than a made-up zero.
    private var stats: Stats {
        guard !workouts.isEmpty else {
            return Stats(duration: workout?.duration ?? 0,
                         distance: workout?.distance ?? 0,
                         elevation: workout?.elevationAscended,
                         calories: workout?.activeCalories)
        }
        var duration: TimeInterval = 0
        var distance: Double = 0
        var elevation: Double?
        var calories: Double?
        for item in workouts {
            duration += item.duration
            distance += item.distance
            if let value = item.elevationAscended { elevation = (elevation ?? 0) + value }
            if let value = item.activeCalories { calories = (calories ?? 0) + value }
        }
        return Stats(duration: duration, distance: distance, elevation: elevation, calories: calories)
    }

    private var statsGrid: some View {
        let distance = Fmt.distanceValue(stats.distance)
        return VStack(spacing: 8) {
            HStack(spacing: 7.3) {
                statCard("Time", Fmt.duration(stats.duration), nil)
                statCard("Distance", distance.value, distance.unit)
            }
            HStack(spacing: 7.3) {
                statCard("Elevation", stats.elevation.map { Fmt.elevation($0) } ?? "--", "m")
                statCard("Active Calories", stats.calories.map { Fmt.caloriesValue($0) } ?? "--", "kcal")
            }
        }
    }

    private func statCard(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Palette.accent)
                if let unit {
                    Text(unit).font(.system(size: 14)).foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6.5)
        .background(Palette.card,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image("SmallIcon")
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            Text("WorkoutMap")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.accent)
        }
    }

    private func cardWidth(_ available: CGFloat) -> CGFloat { min(available * 0.775, 480) }

    private func renderMap() async {
        guard let mapRect, containerWidth > 0 else { return }
        let width = cardWidth(containerWidth)
        let lines = routes.compactMap { line -> RouteLine? in
            guard line.coordinates.count > 1 else { return nil }
            return RouteLine(coordinates: line.coordinates, color: line.color, dash: line.dash)
        }
        mapImage = await MapImageRenderer.shared.image(mapRect: mapRect,
                                                      size: CGSize(width: width, height: width * 0.78),
                                                      scale: displayScale,
                                                      routes: lines,
                                                      mode: mode,
                                                      interfaceStyle: interfaceStyle,
                                                      lineWidth: 4,
                                                      toneChroma: 0,
                                                      toneScale: 0.72)
    }

    private func save() async {
        guard let rendered = preview ?? renderCard() else { failed = true; return }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { failed = true; return }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: rendered)
            }
            saved = true
        } catch {
            failed = true
        }
    }

    private func renderCard() -> UIImage? {
        guard containerWidth > 0 else { return nil }
        let width = cardWidth(containerWidth)
        let content = card(width: width)
        let renderer = ImageRenderer(content: content.frame(width: width).background(Palette.card))
        renderer.scale = displayScale
        return renderer.uiImage
    }
}
