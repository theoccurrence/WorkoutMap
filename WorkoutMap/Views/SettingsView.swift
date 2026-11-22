import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    /// The workouts Health handed over, so an edited one can be named in the list below — and
    /// opened — from here.
    @ObservedObject var health: HealthStore

    @Environment(\.displayScale) private var displayScale
    @State private var showAbout = false
    /// The route edits: the list below, the file they travel in, and the two sheets that move it.
    @ObservedObject private var eraseStore = EraseStore.shared
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var imported: ImportMessage?
    /// The workout an edit's row opened, if any.
    @State private var openedWorkout: Workout?
    /// The edit a bin was tapped for, until its confirmation is answered.
    @State private var pendingDelete: UUID?
    /// The period the map screen opens with. The map reads it when it is built, so a
    /// change here applies from the next launch on.
    @AppStorage(RangeKind.defaultPeriodKey) private var defaultPeriod: RangeKind = .week
    /// How the map is drawn: the system's own light or dark style, or one pinned. The map
    /// reads it live, so a change here redraws it at once.
    @AppStorage(MapAppearance.storedKey) private var mapAppearance: MapAppearance = .system
    /// The two softer jump rules: what counts as a jump, and how each is drawn. The map screens
    /// read them live. The strict three-part detection is not here — it is never drawn.
    @AppStorage(JumpSettings.distanceStyleKey) private var jumpDistanceStyle: RouteJumpStyle = JumpRules.standard.distanceStyle
    @AppStorage(JumpSettings.distanceThresholdKey) private var jumpDistanceThreshold: Double = JumpRules.standard.distanceThreshold
    @AppStorage(JumpSettings.speedStyleKey) private var jumpSpeedStyle: RouteJumpStyle = JumpRules.standard.speedStyle
    @AppStorage(JumpSettings.speedThresholdKey) private var jumpSpeedThreshold: Double = JumpRules.standard.speedThreshold
    /// How many routes the explorer offers at once, and how tight it keeps them. The map screen
    /// reads both when it plans, so a change here applies to the next plan.
    @AppStorage(ExploreOptions.routeCountKey) private var exploreRouteCount: Int = ExploreOptions.routeCountDefault
    @AppStorage(ExploreOptions.shapeKey) private var exploreShape: Double = ExploreOptions.shapeDefault
    /// How much of the route should be new ground.
    @AppStorage(ExploreOptions.minimumNewKey) private var exploreMinimumNew: Double = ExploreOptions.minimumNewDefault
    /// The colour each mode is drawn in — the routes, the position dot and its cone, and the
    /// filter buttons. Shared with the map screens, so a picker here redraws them at once.
    @ObservedObject private var modeColors = CategoryColorStore.shared
    /// The tone each jump rule draws its legs in. Shared with the map screens, the list
    /// thumbnails and the export card, so a picker here redraws them at once.
    @ObservedObject private var jumpColors = JumpColorStore.shared

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
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                    Spacer().frame(height: 33)

                    Text("GPS Jumps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.leading, 2)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Menu {
                            Picker("Distance Jumps", selection: $jumpDistanceStyle) {
                                ForEach(RouteJumpStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                        } label: {
                            rowContent(title: "Distance Jumps",
                                       systemImage: "ruler",
                                       detail: jumpDistanceStyle.title,
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        divider
                        sliderRow(title: "Distance",
                                  systemImage: "arrow.left.and.right",
                                  value: $jumpDistanceThreshold,
                                  range: JumpSettings.distanceRange,
                                  step: JumpSettings.distanceStep,
                                  low: "\(Int(JumpSettings.distanceRange.lowerBound)) m",
                                  high: "\(Int(JumpSettings.distanceRange.upperBound)) m",
                                  detail: "\(Int(jumpDistanceThreshold)) m")
                        // The tone a rule draws its legs in is only worth a row while the rule is
                        // drawn at all: `hidden` leaves nothing for a colour to show up on.
                        if jumpDistanceStyle != .hidden {
                            divider
                            toneRow(.distance, title: "Distance Color")
                        }
                        divider
                        Menu {
                            Picker("Fast Legs", selection: $jumpSpeedStyle) {
                                ForEach(RouteJumpStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                        } label: {
                            rowContent(title: "Fast Legs",
                                       systemImage: "bolt.fill",
                                       detail: jumpSpeedStyle.title,
                                       showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        divider
                        sliderRow(title: "Speed",
                                  systemImage: "speedometer",
                                  value: $jumpSpeedThreshold,
                                  range: JumpSettings.speedRange,
                                  step: JumpSettings.speedStep,
                                  low: "\(Int(JumpSettings.speedRange.lowerBound))",
                                  high: "\(Int(JumpSettings.speedRange.upperBound)) km/h",
                                  detail: "\(Int(jumpSpeedThreshold)) km/h")
                        if jumpSpeedStyle != .hidden {
                            divider
                            toneRow(.speed, title: "Fast Legs Color")
                        }
                        divider
                        resetTonesRow
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                    Text("A leg longer than the distance is drawn as that rule says, and so is a leg faster than the speed — as long as it covers more than \(Int(JumpRules.speedMinimumDistance)) m, since a shorter one is a rounding of the clock and not a jump. A leg that trips both is drawn as a fast leg, and a leg the combined detection catches is never drawn. Each rule draws in its own tone, dotted or solid — the grey and the red until another one is picked above.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 2)
                        .padding(.top, 8)

                    Spacer().frame(height: 33)

                    Text("Mode Colors")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.leading, 2)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(WorkoutCategory.allCases) { category in
                            colorRow(category)
                            if category != WorkoutCategory.allCases.last {
                                divider
                            }
                        }
                        divider
                        resetColorsRow
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

                    workoutEditsSection

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
        .sheet(item: $openedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .fileExporter(isPresented: $showExporter,
                      document: EraseEditsDocument(data: (try? eraseStore.exportData()) ?? Data()),
                      contentType: .json,
                      defaultFilename: "WorkoutMap-Edits") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            imported = message(for: result)
        }
        .confirmationDialog("Remove this edit?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let id = pendingDelete { eraseStore.remove(for: id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The workout's route is drawn whole again. The workout in Health is not changed.")
        }
        .alert(item: $imported) { message in
            Alert(title: Text(message.title), message: Text(message.text),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - workout edits

    /// The route edits: what they are, which workout each belongs to, and the file they can travel
    /// in. The bin removes an edit without the workout ever being opened, and a row opens the
    /// workout while this device still has it.
    private var workoutEditsSection: some View {
        let edits = eraseStore.entries()
        return VStack(alignment: .leading, spacing: 0) {
            Text("Workout Edits")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.leading, 2)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                row(title: "Export Edits",
                    systemImage: "square.and.arrow.up",
                    detail: edits.isEmpty ? nil : "\(edits.count)",
                    showsChevron: true) { showExporter = true }
                divider
                row(title: "Import Edits",
                    systemImage: "square.and.arrow.down",
                    detail: nil,
                    showsChevron: true) { showImporter = true }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            Text("An edit is how this app draws a workout's route — the parts the eraser took out — and never a change to the workout in Health. Export writes every edit to a JSON file; importing one adds the edits that file carries to this device. The same workout keeps the same id in iCloud, so its edits land on the same route — and an edit whose workout this device does not have is kept too, and simply never drawn.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 2)
                .padding(.top, 8)

            if !edits.isEmpty {
                Spacer().frame(height: 18)
                VStack(spacing: 0) {
                    ForEach(Array(edits.enumerated()), id: \.element.id) { index, entry in
                        editRow(entry)
                        if index < edits.count - 1 { divider }
                    }
                }
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
        }
    }

    /// One edited workout. It is named and can be opened while this device has the workout; an id
    /// whose workout is not here — an import from a phone that has more workouts — is still listed,
    /// so the user can see what came over rather than wonder where it went.
    private func editRow(_ entry: EraseStore.Entry) -> some View {
        let workout = health.workouts.first { $0.id == entry.id }
        return HStack(spacing: 8) {
            Button {
                if let workout { openedWorkout = workout }
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
                        Text(workout.map { $0.listDateText } ?? entry.id.uuidString)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
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

    /// What an import had to say. The export writes silently — the share sheet it opens is its own
    /// answer.
    struct ImportMessage: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private func message(for result: Result<URL, Error>) -> ImportMessage {
        guard case .success(let url) = result else {
            return ImportMessage(title: "Could not import", text: "The file could not be opened.")
        }
        // The picker hands a file outside the app's own sandbox, so it is read through the
        // security scope it comes with.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let count = try eraseStore.importData(try Data(contentsOf: url))
            return ImportMessage(title: "Edits imported",
                                 text: count == 1 ? "One edit was added."
                                                  : "\(count) edits were added.")
        } catch {
            return ImportMessage(title: "Could not import",
                                 text: "The file is not a WorkoutMap edits file.")
        }
    }

    /// One mode's colour: its glyph and name, the hex the picker is showing, and the system
    /// colour picker — spectrum, sliders and hex field — on the trailing edge.
    private func colorRow(_ category: WorkoutCategory) -> some View {
        HStack(spacing: 16) {
            Image(systemName: category.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(modeColors.color(for: category))
                .frame(width: 24)
            Text(category.title)
                .font(.system(size: 19))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(modeColors.hexString(for: category))
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
            ColorPicker(category.title,
                        selection: colorBinding(for: category),
                        supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("\(category.title) color")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }

    private func colorBinding(for category: WorkoutCategory) -> Binding<Color> {
        Binding(get: { modeColors.color(for: category) },
                set: { modeColors.setColor($0, for: category) })
    }

    /// One jump rule's tone: its swatch, the hex the picker is showing, and the same system
    /// colour picker the mode colours use. The tone belongs to the rule, so it is what a leg
    /// reads as whether the rule draws that leg dotted or solid.
    private func toneRow(_ kind: JumpKind, title: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(jumpColors.color(for: kind))
                .frame(width: 24)
            Text(title)
                .font(.system(size: 19))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(jumpColors.hexString(for: kind))
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
            ColorPicker(title,
                        selection: toneBinding(for: kind),
                        supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("\(title) tone")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }

    private func toneBinding(for kind: JumpKind) -> Binding<Color> {
        Binding(get: { jumpColors.color(for: kind) },
                set: { jumpColors.setColor($0, for: kind) })
    }

    /// Puts both rules back to the grey and the red they shipped with. Dimmed while there is
    /// nothing to reset.
    private var resetTonesRow: some View {
        Button {
            jumpColors.reset()
        } label: {
            rowContent(title: "Reset Colors",
                       systemImage: "arrow.counterclockwise",
                       detail: nil,
                       showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(jumpColors.isDefault)
        .opacity(jumpColors.isDefault ? 0.45 : 1)
    }

    /// Puts all three modes back to the colours they shipped with. Dimmed while there is
    /// nothing to reset.
    private var resetColorsRow: some View {
        Button {
            modeColors.reset()
        } label: {
            rowContent(title: "Reset to Defaults",
                       systemImage: "arrow.counterclockwise",
                       detail: nil,
                       showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(modeColors.isDefault)
        .opacity(modeColors.isDefault ? 0.45 : 1)
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
                           step: Double? = nil,
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
                Slider(value: value, in: range, step: step ?? 0.01)
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
