import SwiftUI
import MapKit
import CoreLocation

struct WorkoutDetailView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var showExport = DebugLaunch.openExport
    @State private var visibleMapRect: MKMapRect?

    private var lines: [MapRouteLine] {
        [MapRouteLine(id: workout.id.uuidString, coordinates: route, color: workout.category.uiColor)]
    }

    var body: some View {
        GeometryReader { proxy in
            let mapHeight = (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) * 0.5996
            VStack(spacing: 0) {
                mapSection(height: mapHeight)
                stats
                    .padding(.horizontal, 23)
                    .padding(.top, 18)
                footer
                    .padding(.horizontal, 23)
                    .padding(.top, 17)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { shareButton }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: workout.id) {
            route = RouteStore.shared.cached(workout.id) ?? []
            let full = await RouteStore.shared.route(for: workout.hk)
            if !full.isEmpty { route = full }
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportPreviewView(workout: workout,
                              rangeLabel: workout.listDateText,
                              mapRect: visibleMapRect ?? RouteGeometry.fittedRect(routes: [route]),
                              routes: lines)
        }
    }

    private func mapSection(height: CGFloat) -> some View {
        RouteMapView(routes: lines,
                     camera: RouteGeometry.fittedRect(routes: [route]).map { .fit($0) },
                     cameraToken: route.count,
                     onRegionChange: { visibleMapRect = $0 })
            .frame(height: height)
            .clipped()
            .overlay(alignment: .bottomLeading) { mapOverlay }
            .overlay(alignment: .bottomTrailing) { weatherOverlay }
    }

    private var mapOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Image(systemName: workout.category.symbolName)
                    .font(.system(size: 33, weight: .regular))
                    .foregroundStyle(Palette.accent)
                Text(workout.category.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            Text(workout.detailDateText)
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
        .padding(.leading, 23)
        .padding(.bottom, 40)
    }

    private var weatherOverlay: some View {
        HStack(spacing: 14) {
            if let temperature = workout.temperature {
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium").font(.system(size: 15))
                    Text(Fmt.temperature(temperature)).font(.system(size: 17))
                }
            }
            if let humidity = workout.humidity {
                HStack(spacing: 5) {
                    Image(systemName: "humidity.fill").font(.system(size: 15))
                    Text(Fmt.humidity(humidity)).font(.system(size: 17))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.trailing, 22)
        .padding(.bottom, 44)
    }

    private var stats: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                StatCard(label: "Time", value: Fmt.duration(workout.duration), unit: nil)
                StatCard(label: "Distance",
                         value: Fmt.distanceValue(workout.distance).value,
                         unit: Fmt.distanceValue(workout.distance).unit)
            }
            HStack(spacing: 20) {
                StatCard(label: "Elevation",
                         value: workout.elevationAscended.map { Fmt.elevation($0) } ?? "--",
                         unit: "m")
                StatCard(label: "Active Calories",
                         value: workout.activeCalories.map { Fmt.caloriesValue($0) } ?? "--",
                         unit: "kcal")
            }
            HStack(spacing: 20) {
                StatCard(label: "Avg. Pace",
                         value: Fmt.pace(workout.duration, meters: workout.distance),
                         unit: "/km")
                StatCard(label: "Avg. Heart Rate",
                         value: workout.avgHeartRate.map { Fmt.heartRate($0) } ?? "--",
                         unit: "bpm")
            }
        }
    }

    private var footer: some View {
        Text("*Data from \(workout.sourceName)")
            .font(.system(size: 15))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }

    private var shareButton: some View {
        Button { showExport = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.accent)
                if let unit {
                    Text(unit)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 10.5)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.statCardRadius, style: .continuous))
    }
}
