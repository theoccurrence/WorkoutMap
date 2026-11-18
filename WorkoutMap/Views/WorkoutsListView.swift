import SwiftUI

struct WorkoutsListView: View {
    @ObservedObject var health: HealthStore

    @State private var path: [Workout] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                AppBackground()
                content
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: health.workouts.count) { _, _ in openDebugDetailIfNeeded() }
            .onAppear { openDebugDetailIfNeeded() }
        }
    }

    private func openDebugDetailIfNeeded() {
        guard DebugLaunch.openDetail, path.isEmpty, let first = health.workouts.first else { return }
        path = [first]
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.cardGap) {
                Text("Workouts")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.top, 41)
                    .padding(.bottom, 26)

                ForEach(health.workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutCardView(workout: workout)
                    }
                    .buttonStyle(.plain)
                }

                if health.didLoad && health.workouts.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await health.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(health.status == .unavailable ? "Health data unavailable" : "No workouts")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(health.status == .unavailable
                 ? "This device has no Health database."
                 : "Allow WorkoutMap to read your workouts in Settings > Privacy > Health.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
    }
}
