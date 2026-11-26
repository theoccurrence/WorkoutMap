import SwiftUI
import MapKit
import UIKit

/// What a card is *of*: one workout, or the whole map as the filter leaves it.
enum ShareSubject {
    case workout(Workout)
    case map(workouts: [Workout], rangeLabel: String)
}

/// What a card says under its numbers.
enum ShareFooter {
    /// The app's own badge. The whole map carries it, and so does **every** image the two *Save*
    /// buttons write — the file is the app's, whatever it is of.
    case badge
    /// Where a workout's numbers came from — what the detail **screen** carries, and only the screen:
    /// the badge goes on the image.
    case source
}

/// The app's own card — the map with its overlay, the six numbers and the footer — as one view.
///
/// It is the detail screen's own layout (`WorkoutDetailView`), lifted out so that the screen and the
/// image *Save* writes are drawn from the same code: on the screen it is handed the **live** map, and
/// the image *Save* writes is that same live map's own rendering, at the card's own size
/// (`ShareImageRenderer`). A card is therefore never a promise the file does not keep — and so that
/// stays true of a **tilted** map, whose routes and 3D blocks only exist together in the live map's
/// rendering, the image is the view itself and not a snapshot of the region it frames.
struct ShareCard<Map: View>: View {
    let subject: ShareSubject
    /// The map itself: the live one on the screen, a snapshot when the card is being rendered.
    let map: Map
    let size: CGSize
    /// Which footer to draw. See `ShareFooter`.
    var footerStyle: ShareFooter = .badge
    /// How tall the numbers-and-footer block stands, reported as it is measured: the rail hangs on
    /// its top edge, and only the screen that draws the rail needs the number.
    var onBlockHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) { mapBottomRow }
            VStack(spacing: 0) {
                stats
                    .padding(.horizontal, 23)
                    .padding(.top, 18)
                footer
                    .padding(.horizontal, 23)
                    .padding(.top, 17)
                    // The footer is centred in the room the numbers leave: the same gap above it as
                    // below, rather than sitting against the card's bottom edge.
                    //
                    // The gap is on **both** footers, and that is not only a look: the block's own
                    // height is what tells the card how much of it is map, and the screen measures it
                    // with one footer while the file is drawn with the other. A source line with no
                    // room under it and a badge with 17 pt made the two blocks differ by 19 pt, so the
                    // file — laid out at the display's width, with the badge — ran that much taller
                    // than the map it had been given and pushed its own footer off the bottom edge
                    // (measured). One height for both is what keeps them the same card.
                    .padding(.bottom, 17)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onBlockHeight($0.height) }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
    }

    /// The map's bottom edge: the title and date on the left, the weather on the right — **one row**,
    /// so the date and the weather sit on the same line instead of a few points apart.
    ///
    /// Both are the accent rather than white. White over the map's greens and greys read as a glare
    /// against the background; the accent is what the title above them already is, so the row reads
    /// as one block.
    private var mapBottomRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            title
            Spacer(minLength: 12)
            weather
        }
        .foregroundStyle(Palette.accent)
        .padding(.leading, 23)
        .padding(.trailing, 22)
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch subject {
            case .workout(let workout):
                HStack(spacing: 12) {
                    Image(systemName: workout.category.symbolName)
                        .font(.system(size: 33, weight: .regular))
                    Text(workout.category.title)
                        .font(.system(size: 30, weight: .bold))
                }
                Text(workout.detailDateText)
                    .font(.system(size: 17))
            case .map(_, let rangeLabel):
                Text("Workout Map")
                    .font(.system(size: 30, weight: .bold))
                Text(rangeLabel)
                    .font(.system(size: 17))
            }
        }
    }

    /// The workout's weather, where it has any — on the date's own line. The whole map carries none:
    /// a set of workouts has no one temperature.
    @ViewBuilder
    private var weather: some View {
        if case .workout(let workout) = subject {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                if let temperature = workout.temperature {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Image(systemName: "thermometer.medium").font(.system(size: 15))
                        Text(Fmt.temperature(temperature)).font(.system(size: 17))
                    }
                }
                if let humidity = workout.humidity {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Image(systemName: "humidity.fill").font(.system(size: 15))
                        Text(Fmt.humidity(humidity)).font(.system(size: 17))
                    }
                }
            }
        }
    }

    /// One of the six numbers under the map, and the unit it is read in.
    private struct Stat {
        let label: String
        let value: String
        let unit: String?
    }

    /// The six numbers, in the grid the card's shape asks for: **three rows of two standing up, two
    /// rows of three lying down**, so the block is never taller than it has to be and the map above
    /// keeps the rest.
    private var stats: some View {
        let columns = size.width > size.height ? 3 : 2
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

    /// The numbers themselves: the one workout's own, or the sum over the map's set.
    ///
    /// The sum is what the numbers *mean* for a set: time, distance, elevation and active energy all
    /// add up across workouts. Pace is the set's own — its total time over its total distance — and
    /// heart rate is averaged over the *time* each workout ran, so a long walk weighs more than a
    /// short one. Elevation, calories and heart rate stay `nil` when no workout in the set carries
    /// them, so the card shows `--` rather than a made-up zero.
    private var statItems: [Stat] {
        switch subject {
        case .workout(let workout):
            return Self.items(duration: workout.duration,
                              distance: workout.distance,
                              elevation: workout.elevationAscended,
                              calories: workout.activeCalories,
                              heartRate: workout.avgHeartRate)
        case .map(let workouts, _):
            var duration: TimeInterval = 0
            var distance: Double = 0
            var elevation: Double?
            var calories: Double?
            var heartRateSum: Double = 0
            var heartRateSeconds: TimeInterval = 0
            for item in workouts {
                duration += item.duration
                distance += item.distance
                if let value = item.elevationAscended { elevation = (elevation ?? 0) + value }
                if let value = item.activeCalories { calories = (calories ?? 0) + value }
                if let bpm = item.avgHeartRate, item.duration > 0 {
                    heartRateSum += bpm * item.duration
                    heartRateSeconds += item.duration
                }
            }
            return Self.items(duration: duration,
                              distance: distance,
                              elevation: elevation,
                              calories: calories,
                              heartRate: heartRateSeconds > 0 ? heartRateSum / heartRateSeconds : nil)
        }
    }

    private static func items(duration: TimeInterval,
                              distance: Double,
                              elevation: Double?,
                              calories: Double?,
                              heartRate: Double?) -> [Stat] {
        let value = Fmt.distanceValue(distance)
        return [
            Stat(label: "Time", value: Fmt.duration(duration), unit: nil),
            Stat(label: "Distance", value: value.value, unit: value.unit),
            Stat(label: "Elevation",
                 value: elevation.map { Fmt.elevation($0) } ?? "--",
                 unit: "m"),
            Stat(label: "Active Calories",
                 value: calories.map { Fmt.caloriesValue($0) } ?? "--",
                 unit: "kcal"),
            Stat(label: "Avg. Pace",
                 value: Fmt.pace(duration, meters: distance),
                 unit: "/km"),
            Stat(label: "Avg. Heart Rate",
                 value: heartRate.map { Fmt.heartRate($0) } ?? "--",
                 unit: "bpm")
        ]
    }

    /// The source line is the screen's own, and only a workout has one.
    private var showsSource: Bool {
        if case .workout = subject, footerStyle == .source { return true }
        return false
    }

    /// Under the numbers: where a workout's numbers came from, or the app's own badge.
    @ViewBuilder
    private var footer: some View {
        if showsSource, case .workout(let workout) = subject {
            Text("*Data from \(workout.sourceName)")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 7) {
                Image("SmallIcon")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                Text("WorkoutMap")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Renders a card into the one image *Save* writes: the map first — the card cannot be drawn without it
/// — and the card's own layout over it at the card's own size, so the file is the card and nothing else:
/// no buttons, no status bar.
///
/// The map is the **live** map view's own rendering, for every card and every camera
/// (`MapImageRenderer.liveImage`). That is what keeps a tilted map honest: the routes are drawn *inside*
/// MapKit's own render pass on the screen, so the 3D blocks occlude them the way the user sees — a
/// snapshot cannot do that, and a route drawn by hand into one lies across the buildings it should pass
/// behind. It also means the file carries whatever the map is showing, tone pass and MapKit's own *Maps*
/// line included, rather than an approximation of them.
@MainActor
enum ShareImageRenderer {
    /// The size every image is written at: the display's own, whatever box the screen that asked for
    /// it was drawn in. A card of the map screen is inset by `Metrics.menuCardInset` on every side
    /// (`MapTabView.menuLayer`), and the detail screen is inset by it when it is that screen's own
    /// card — so the screen's box plus those margins is the display, and the file comes out the same
    /// size whether it was written from a card or from a pushed screen.
    static func displaySize(for box: CGSize) -> CGSize {
        CGSize(width: box.width + Metrics.menuCardInset * 2,
               height: box.height + Metrics.menuCardInset * 2)
    }

    /// The card over the map a **live** view is showing — every card, whatever its camera.
    ///
    /// A live map view is the only place the app's routes and the 3D blocks are drawn *together*, with
    /// the depth between them: on the screen the routes are `MKOverlay`s inside MapKit's own render pass,
    /// so a building in front of one hides it. A snapshot cannot carry that — it cannot carry the routes
    /// at all, and a line drawn by hand into one has no depth, so it lies across the buildings it should
    /// pass behind, which is not the map the user was looking at. The view is the screen's own map, so
    /// the file is that map: the tone pass, the labels and MapKit's own *Maps* line with it.
    ///
    /// `nil` when the view has nothing to draw — never laid out, or never on screen — which is the one
    /// case *Save* cannot answer.
    static func image(subject: ShareSubject, mapView: UIView?, size: CGSize, scale: CGFloat) -> UIImage? {
        guard let mapView,
              let mapImage = MapImageRenderer.liveImage(of: mapView, scale: scale) else { return nil }
        return image(subject: subject, mapImage: mapImage, size: size, scale: scale)
    }

    /// The card over a map already rendered — the map view's own rendering, so what *Save* writes is the
    /// very map the screen is showing.
    static func image(subject: ShareSubject, mapImage: UIImage?, size: CGSize, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: card(subject: subject, mapImage: mapImage, size: size))
        renderer.scale = scale
        return renderer.uiImage
    }

    private static func card(subject: ShareSubject, mapImage: UIImage?, size: CGSize) -> some View {
        ShareCard(subject: subject, map: snapshot(mapImage), size: size)
    }

    @ViewBuilder
    private static func snapshot(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(red: 0.09, green: 0.09, blue: 0.1)
        }
    }
}
