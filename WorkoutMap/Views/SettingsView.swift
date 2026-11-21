import SwiftUI

struct SettingsView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var showAbout = false
    /// The period the map screen opens with. The map reads it when it is built, so a
    /// change here applies from the next launch on.
    @AppStorage(RangeKind.defaultPeriodKey) private var defaultPeriod: RangeKind = .week
    /// How the map is drawn: the system's own light or dark style, or one pinned. The map
    /// reads it live, so a change here redraws it at once.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance = .system
    /// What the map does with a GPS jump: the dashed grey line the Fitness app draws across
    /// ground the workout never measured, or nothing at all. The map screens read it live.
    @AppStorage(RouteJumpStyle.storedKey) private var jumpStyle: RouteJumpStyle = .dotted
    /// How many routes the explorer offers at once, and how tight it keeps them. The map screen
    /// reads both when it plans, so a change here applies to the next plan.
    @AppStorage(ExploreOptions.routeCountKey) private var exploreRouteCount: Int = ExploreOptions.routeCountDefault
    @AppStorage(ExploreOptions.shapeKey) private var exploreShape: Double = ExploreOptions.shapeDefault
    /// How much of the route should be new ground.
    @AppStorage(ExploreOptions.minimumNewKey) private var exploreMinimumNew: Double = ExploreOptions.minimumNewDefault

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2)
                        .padding(.top, 41)
                        .padding(.bottom, 26)

                    VStack(spacing: 0) {
                        row(title: "Data Source",
                            systemImage: "heart.text.square",
                            detail: "Health",
                            showsChevron: true) {}
                        divider
                        Menu {
                            Picker("Default Period", selection: $defaultPeriod) {
                                ForEach(RangeKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                        } label: {
                            rowContent(title: "Default Period",
                                       systemImage: "calendar",
                                       detail: defaultPeriod.title,
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        divider
                        Menu {
                            Picker("Map Appearance", selection: $mapAppearance) {
                                ForEach(MapAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                        } label: {
                            rowContent(title: "Map Appearance",
                                       systemImage: "circle.lefthalf.filled",
                                       detail: mapAppearance.title,
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        divider
                        Menu {
                            Picker("GPS Jumps", selection: $jumpStyle) {
                                ForEach(RouteJumpStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                        } label: {
                            rowContent(title: "GPS Jumps",
                                       systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       detail: jumpStyle.title,
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                    Spacer().frame(height: 33)

                    Text("Explore")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.leading, 2)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Menu {
                            Picker("Routes Suggested", selection: $exploreRouteCount) {
                                ForEach(ExploreOptions.routeCounts, id: \.self) { count in
                                    Text(count == 1 ? "1 route" : "\(count) routes").tag(count)
                                }
                            }
                        } label: {
                            rowContent(title: "Routes Suggested",
                                       systemImage: "list.number",
                                       detail: "\(exploreRouteCount)",
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        divider
                        shapeRow
                        divider
                        newWaysRow
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                    Spacer().frame(height: 33)

                    VStack(spacing: 0) {
                        row(title: "Feedback", systemImage: "square.and.pencil", detail: nil, showsChevron: true) {
                            open("mailto:feedback@theoccurrence.com?subject=WorkoutMap%20Feedback")
                        }
                        divider
                        row(title: "Share App", systemImage: "square.and.arrow.up", detail: nil, showsChevron: true) { showAbout = false }
                        divider
                        row(title: "About WorkoutMap", systemImage: "info.circle", detail: nil, showsChevron: true) { showAbout = true }
                        divider
                        row(title: "Contact us", systemImage: "envelope", detail: nil, showsChevron: true) {
                            open("mailto:hello@theoccurrence.com?subject=WorkoutMap")
                        }
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .padding(.horizontal, Metrics.contentInset)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .alert("WorkoutMap", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Version 1.0")
        }
    }

    /// The shape slider: at *Wide* the planner makes two long legs out and back around the
    /// start (or one big bow to a destination); at *Tight* it fills the streets around the route
    /// in as many small steps as the request budget pays for.
    private var shapeRow: some View {
        sliderRow(title: "Route Shape",
                  systemImage: "slider.horizontal.3",
                  value: $exploreShape,
                  range: 0...1,
                  low: "Wide",
                  high: "Tight",
                  detail: ExploreOptions.shapeLabel(exploreShape))
    }

    /// The new-ways slider: how much of the route the planner should try to keep on ground the
    /// user has never covered. A target rather than a guarantee — see `ExploreOptions`.
    private var newWaysRow: some View {
        sliderRow(title: "New Ways",
                  systemImage: "sparkles",
                  value: $exploreMinimumNew,
                  range: ExploreOptions.minimumNewRange,
                  low: "10%",
                  high: "100%",
                  detail: ExploreOptions.percentLabel(exploreMinimumNew))
    }

    private func sliderRow(title: String,
                           systemImage: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           low: String,
                           high: String,
                           detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 10) {
                Text(low)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                Slider(value: value, in: range)
                    .tint(Palette.accent)
                Text(high)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(height: 1 / displayScale)
            .padding(.leading, 56)
    }

    private func row(title: String,
                     systemImage: String,
                     detail: String?,
                     showsChevron: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(title: title, systemImage: systemImage, detail: detail, showsChevron: showsChevron)
        }
        .buttonStyle(.plain)
    }

    /// One row of a card. Shared with the rows that are menus rather than buttons.
    private func rowContent(title: String,
                            systemImage: String,
                            detail: String?,
                            showsChevron: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 19))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
