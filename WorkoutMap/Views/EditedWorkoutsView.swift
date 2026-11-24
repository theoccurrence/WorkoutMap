import SwiftUI

/// The settings screen's list of edited workouts — the screen behind *Workout Edits ▸ Edited
/// Workouts*, so the settings screen itself stays short however many workouts carry an edit.
///
/// A row names its workout and opens it; the bin beside it removes that workout's edit without the
/// workout ever being opened. An edit whose workout this device does not have — an import from a
/// phone that has more workouts — is listed too, so the user can see what came over rather than
/// wonder where it went, but it cannot be opened: there is nothing here to open.
struct EditedWorkoutsView: View {
    @ObservedObject var health: HealthStore

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RouteEditStore.shared
    /// The workout a row pushed, and with it the whole navigation path.
    @State private var path: [Workout] = []
    /// The edit a bin was tapped for, until its confirmation is answered.
    @State private var pendingDelete: UUID?

    private var entries: [RouteEditStore.Entry] { store.entries() }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        content
                    }
                    .padding(.horizontal, Metrics.contentInset)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Workout.self) { workout in
                // Pushed, not drawn as a card of its own: inside this sheet the *sheet's* card is the
                // card, and a screen that insets itself again leaves the system's own fill showing in
                // the margin — the grey bar under the card's bottom edge (measured: the band stays
                // `(28, 28, 30)` whatever `presentationBackground` is told). Filling the card whole
                // leaves nothing of it to show.
                WorkoutDetailView(workout: workout, presentation: .pushed)
            }
        }
        // WM_EDITS_DETAIL=1 — see `DebugLaunch.openEditsDetail`: the row the simulator cannot tap, so
        // the card it pushes can be shot. The wait comes first because the workouts are read from
        // Health, which is still bootstrapping when this screen opens.
        .task {
            guard DebugLaunch.openEditsDetail, path.isEmpty else { return }
            try? await Task.sleep(for: .seconds(2))
            if let workout = health.workouts.first { path = [workout] }
        }
        .confirmationDialog("Remove this edit?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let id = pendingDelete { store.remove(for: id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The workout's route is drawn whole again, and a jump flagged on it goes back to being one. The workout in Health is not changed.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Edited Workouts")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            CloseCircleButton { dismiss() }
        }
        .padding(.horizontal, 2)
        .padding(.top, 41)
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            Text("No edited workouts. Open one from the list and use the brush there: its route can have ground erased, or a GPS jump flagged as ground that really was covered.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 2)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                    if index < entries.count - 1 { RowDivider() }
                }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    /// One edited workout: what it is, what the edit does to it, and its bin.
    private func row(_ entry: RouteEditStore.Entry) -> some View {
        let workout = health.workouts.first { $0.id == entry.id }
        return HStack(spacing: 8) {
            Button {
                if let workout { path.append(workout) }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: workout?.category.symbolName ?? "questionmark.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(workout == nil ? Palette.textSecondary : .white)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout?.title ?? "Workout not on this device")
                            .font(.system(size: 19))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle(entry, workout: workout))
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(workout == nil)

            Button { pendingDelete = entry.id } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove edit")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 70)
    }

    /// What the row says under the name: when the workout was, and what the edit does to its route —
    /// or the id alone when this device has no such workout to ask.
    private func subtitle(_ entry: RouteEditStore.Entry, workout: Workout?) -> String {
        guard let workout else { return entry.id.uuidString }
        return "\(workout.listDateText) · \(entry.edits.summary)"
    }
}
