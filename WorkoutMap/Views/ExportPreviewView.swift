import SwiftUI
import MapKit
import Photos
import CoreLocation

struct ExportPreviewView: View {
    let workout: Workout?
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
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    CloseCircleButton { dismiss() }
                }
                .padding(.trailing, 35)
                .padding(.top, 3)

                card(width: cardWidth(proxy.size.width))
                    .padding(.top, 46)

                Spacer(minLength: 0)

                PrimaryButton(title: "Save") { Task { await save() } }
                    .padding(.bottom, 62)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in containerWidth = width }
        }
        .task(id: containerWidth) { await renderMap() }
        .alert("Saved to Photos", isPresented: $saved) { Button("OK", role: .cancel) {} }
        .alert("Could not save", isPresented: $failed) { Button("OK", role: .cancel) {} }
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

    private var statsGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7.3) {
                statCard("Time", Fmt.duration(workout?.duration ?? 0), nil)
                statCard("Distance", workout.map { Fmt.distanceValue($0.distance).value } ?? "--",
                         workout.map { Fmt.distanceValue($0.distance).unit })
            }
            HStack(spacing: 7.3) {
                statCard("Elevation", workout?.elevationAscended.map { Fmt.elevation($0) } ?? "--", "m")
                statCard("Active Calories", workout?.activeCalories.map { Fmt.caloriesValue($0) } ?? "--", "kcal")
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
            return RouteLine(coordinates: line.coordinates, color: line.color)
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
        guard let rendered = renderCard() else { failed = true; return }
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
