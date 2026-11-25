import SwiftUI
import MapKit
import CoreLocation

/// The explorer's input panel: a loop or a walk to a destination, and how far.
///
/// Drawn as one of the map screen's own cards (`View.menuCard()`), the same shape as the sheet the
/// range bubble opens — and the same card the map screen's other two menus are drawn on — rather
/// than presented as a sheet: a sheet lies over the screen's rail on the Duo, and the panel has to
/// be handed the room the keyboard leaves it, which a half-height sheet's own detent does not do.
///
/// A destination is either a search result (`MKLocalSearchCompleter`, as Maps' own search does)
/// or the pin the user dropped on the map — one pin at a time, a new one replacing the old.
struct RoutePlannerPanel: View {
    @Binding var mode: PlanMode
    @Binding var kilometers: Double
    @Binding var destination: PlanDestination?
    /// The pin on the map, if there is one, offered as a destination as well.
    let droppedPin: CLLocationCoordinate2D?
    /// The region the search is biased to — the map's own area.
    let region: MKCoordinateRegion?
    /// True while the routes that were not on disk yet are still being read.
    let isReadingRoutes: Bool
    /// How much room the panel has to work with, so that the keyboard — which pushes the panel up
    /// but cannot make it taller — never takes the header and the close cross off the screen.
    let room: CGFloat
    var onClose: () -> Void
    var onPlan: (PlanRequest) -> Void

    @StateObject private var search = DestinationSearch()
    @FocusState private var searchFocused: Bool

    private var canPlan: Bool { mode == .loop || destination != nil }

    /// The panel's own height: what the sheet it used to be was handed as a detent. A destination
    /// needs the room for the search field, the results and the pin — and no more. The destination
    /// part is a `ScrollView`, so the panel does not have to be built tall enough for all of them at
    /// once, and built that tall it reached the top of the display and put its own close cross under
    /// the status elements as soon as the keyboard pushed it up, which is why it gives that room back.
    private var height: CGFloat { min(mode == .loop ? 340 : 440, room) }

    /// The mode picker's own binding: what changes with the mode is the panel's **height**, so the
    /// change is made inside an animation rather than in the tap's own transaction — the card grows
    /// and shrinks with it (`height`) instead of jumping, which is what it used to do.
    private var animatedMode: Binding<PlanMode> {
        Binding(get: { mode },
                set: { next in
                    guard next != mode else { return }
                    withAnimation(MenuMotion.animation) { mode = next }
                })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            distance
            if mode == .destination {
                // The destination part scrolls rather than growing: with the keyboard up there is
                // not the room for it, and the header and Plan route have to stay where they are.
                ScrollView { destinationSection }
                    .scrollIndicators(.hidden)
            } else {
                Spacer(minLength: 0)
            }
            PrimaryButton(title: "Plan route") { plan() }
                .opacity(canPlan ? 1 : 0.4)
                .disabled(!canPlan)
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, 16)
        }
        .frame(height: height)
        // On the card's own top-trailing corner, on the column the map screen's toolbar keeps —
        // see `MapModePanel`, which is the same arrangement.
        .overlay(alignment: .topTrailing) {
            MenuCloseButton { onClose() }
                .padding(.top, Metrics.menuCardCrossInset)
                .padding(.trailing, Metrics.menuCardCrossInset)
        }
        .onAppear {
            search.region = region
            if DebugLaunch.focusSearch { searchFocused = true }
        }
        .onChange(of: region?.center.latitude) { _, _ in search.region = region }
    }

    private var header: some View {
        Text("Explore")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.menuHeaderHeight)
            .padding(.top, Metrics.menuCardCrossInset)
    }

    private var modePicker: some View {
        Picker("Mode", selection: animatedMode) {
            ForEach(PlanMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 16)
    }

    private var distance: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Distance")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if isReadingRoutes {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.textSecondary)
                    Text("reading your routes…")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text(distanceText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            Slider(value: $kilometers, in: 1...20, step: 0.5)
                .tint(Palette.accent)
        }
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 20)
    }

    private var distanceText: String {
        String(format: "%.1f km", kilometers)
    }

    // MARK: - Destination

    @ViewBuilder
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Destination")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            if let destination {
                chosen(destination)
            } else {
                searchField
                if !search.results.isEmpty { results }
                pinRow
            }
        }
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 20)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
            TextField("Search for a place", text: $search.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(Array(search.results.prefix(4).enumerated()), id: \.offset) { _, completion in
                Button {
                    choose(completion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if completion.title != search.results.prefix(4).last?.title { divider }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var pinRow: some View {
        Button {
            guard let droppedPin else { return }
            destination = PlanDestination(coordinate: droppedPin, name: "Pin on the map", isPin: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(droppedPin == nil ? Palette.textSecondary : Palette.pin)
                Text(droppedPin == nil
                     ? "Press and hold the map to drop a pin"
                     : "Use the pin on the map")
                    .font(.system(size: 15))
                    .foregroundStyle(droppedPin == nil ? Palette.textSecondary : Color.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(droppedPin == nil)
    }

    private func chosen(_ destination: PlanDestination) -> some View {
        HStack(spacing: 8) {
            Image(systemName: destination.isPin ? "mappin.circle.fill" : "mappin.and.ellipse")
                .font(.system(size: 16))
                .foregroundStyle(destination.isPin ? Palette.pin : Palette.accent)
            Text(destination.name)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button {
                self.destination = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 12)
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        Task {
            if let resolved = await search.resolve(completion) {
                destination = resolved
                search.clear()
            }
        }
    }

    private func plan() {
        let request = PlanRequest(mode: mode,
                                  targetMeters: kilometers * 1000,
                                  destination: mode == .destination ? destination?.coordinate : nil,
                                  destinationName: mode == .destination ? destination?.name : nil)
        onClose()
        onPlan(request)
    }
}

/// The destination search: `MKLocalSearchCompleter` for the suggestions, `MKLocalSearch` to turn
/// the one the user picks into a coordinate.
@MainActor
final class DestinationSearch: NSObject, ObservableObject {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    var region: MKCoordinateRegion? {
        didSet {
            guard let region else { return }
            completer.region = region
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Drops the current suggestions, once one of them has been picked.
    func clear() {
        query = ""
        results = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> PlanDestination? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        let name = completion.title.isEmpty ? completion.subtitle : completion.title
        return PlanDestination(coordinate: coordinate, name: name, isPin: false)
    }
}

extension DestinationSearch: MKLocalSearchCompleterDelegate {
    // The completer calls back on the main queue (`delegateQueue` is nil), so the hop is a
    // statement of fact rather than a move.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { results = [] }
    }
}
