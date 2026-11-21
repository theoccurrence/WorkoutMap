import SwiftUI
import MapKit
import CoreLocation

/// The explorer's input sheet: a loop or a walk to a destination, and how far.
///
/// A destination is either a search result (`MKLocalSearchCompleter`, as Maps' own search does)
/// or the pin the user dropped on the map — one pin at a time, a new one replacing the old.
struct RoutePlannerSheet: View {
    @Binding var mode: PlanMode
    @Binding var kilometers: Double
    @Binding var destination: PlanDestination?
    /// The pin on the map, if there is one, offered as a destination as well.
    let droppedPin: CLLocationCoordinate2D?
    /// The region the search is biased to — the map's own area.
    let region: MKCoordinateRegion?
    /// True while the routes that were not on disk yet are still being read.
    let isReadingRoutes: Bool
    var onPlan: (PlanRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = DestinationSearch()

    private var canPlan: Bool { mode == .loop || destination != nil }

    private var detent: CGFloat { mode == .loop ? 340 : 560 }

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            distance
            if mode == .destination {
                destinationSection
            }
            Spacer(minLength: 0)
            PrimaryButton(title: "Plan route") { plan() }
                .opacity(canPlan ? 1 : 0.4)
                .disabled(!canPlan)
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, 23)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel()
        .presentationDetents([.height(detent)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(12)
        .onAppear { search.region = region }
        .onChange(of: region?.center.latitude) { _, _ in search.region = region }
    }

    private var header: some View {
        ZStack {
            Text("Explore")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            HStack {
                Spacer()
                CloseCircleButton { dismiss() }
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 14)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
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
        dismiss()
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
