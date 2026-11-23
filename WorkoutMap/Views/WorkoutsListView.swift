import SwiftUI

/// How the workouts list is ordered. The choice is kept in the settings, so the list opens the
/// way it was last left.
enum WorkoutSort: String, CaseIterable, Identifiable {
    /// Newest first.
    case date
    /// Longest first — the distance the workout covered.
    case length

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date"
        case .length: return "Length"
        }
    }

    var symbolName: String {
        switch self {
        case .date: return "calendar"
        case .length: return "ruler"
        }
    }

    static let storedKey = "workoutSort"
}

struct WorkoutsListView: View {
    @ObservedObject var health: HealthStore

    @State private var path: [Workout] = []
    @AppStorage(WorkoutSort.storedKey) private var sort: WorkoutSort = .date

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                AppBackground()
                content
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout, presentation: .pushed)
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

    /// The workouts in the order the sort asks for. Date puts the newest first; length puts the
    /// longest first, and two equal distances fall back to the newer one, so the order is
    /// stable and never jitters between reloads.
    private var sortedWorkouts: [Workout] {
        switch sort {
        case .date:
            return health.workouts.sorted { $0.start > $1.start }
        case .length:
            return health.workouts.sorted {
                $0.distance == $1.distance ? $0.start > $1.start : $0.distance > $1.distance
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.cardGap) {
                HStack(spacing: 12) {
                    Text("Workouts")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    sortMenu
                }
                .padding(.horizontal, 2)
                .padding(.top, 41)
                .padding(.bottom, 26)

                ForEach(sortedWorkouts) { workout in
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

    /// The list's order — date or length — as the one control the header carries. Its label
    /// shows the order that is on, so the list never needs a second row to say it.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(WorkoutSort.allCases) { option in
                    Label(option.title, systemImage: option.symbolName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text(sort.title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Palette.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort workouts")
        .accessibilityValue(sort.title)
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
