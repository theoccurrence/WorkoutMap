import SwiftUI

/// The range picker: the week / month / year the map is filtered to, as a wheel — drawn as one of
/// the map screen's own panels rather than presented as a sheet, so it keeps the screen's chrome
/// (the Duo's rail and its tab registers) clear, like the range bubble it is opened from. See
/// `View.glassPanel()` for what a half-height sheet's card does to that chrome.
struct RangePickerPanel: View {
    @Binding var selection: RangeSelection
    let workouts: [Workout]
    /// How much room the panel has to work with (`MapTabView.menuPanel`).
    let room: CGFloat
    var onClose: () -> Void

    @State private var weekOffset: Int = 0
    @State private var month: Int = 1
    @State private var year: Int = 2026

    /// The panel's own height: what the sheet it used to be was handed as a detent.
    private var height: CGFloat { min(358, room) }

    private var weekOffsets: [Int] { RangeSelection.weekOptions(from: workouts) }
    private var years: [Int] { RangeSelection.yearOptions }

    var body: some View {
        VStack(spacing: 0) {
            header
            wheels
            Spacer(minLength: 0)
            PrimaryButton(title: "Done") { onClose() }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, 16)
        }
        .frame(height: height)
        .glassPanel()
        .onAppear(perform: syncFromSelection)
        .onChange(of: weekOffset) { _, _ in pushSelection() }
        .onChange(of: month) { _, _ in pushSelection() }
        .onChange(of: year) { _, _ in pushSelection() }
    }

    private var header: some View {
        ZStack {
            Text(selection.kind.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            HStack {
                Spacer()
                CloseCircleButton { onClose() }
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var wheels: some View {
        Group {
            switch selection.kind {
            case .week:
                Picker("", selection: $weekOffset) {
                    ForEach(weekOffsets, id: \.self) { offset in
                        Text(AppCalendar.weekLabel(offset: offset)).tag(offset)
                    }
                }
                .pickerStyle(.wheel)
            case .month:
                HStack(spacing: 0) {
                    Picker("", selection: $month) {
                        ForEach(1...12, id: \.self) { value in
                            Text(monthName(value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    Picker("", selection: $year) {
                        ForEach(years, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            case .year:
                Picker("", selection: $year) {
                    ForEach(years, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
            case .all:
                Picker("", selection: $year) {
                    ForEach(years, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .disabled(true)
                .opacity(0.4)
            }
        }
        .frame(height: 216)
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 6)
    }

    private func monthName(_ value: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = value
        comps.day = 1
        guard let date = AppCalendar.calendar.date(from: comps) else { return "\(value)" }
        return Fmt.monthYear.string(from: date).components(separatedBy: " ").first ?? "\(value)"
    }

    private func syncFromSelection() {
        switch selection {
        case .week(let offset):
            weekOffset = weekOffsets.contains(offset) ? offset : 0
        case .month(let m, let y):
            month = m
            year = years.contains(y) ? y : (years.first ?? y)
        case .year(let y):
            year = years.contains(y) ? y : (years.first ?? y)
        case .all:
            break
        }
    }

    private func pushSelection() {
        switch selection.kind {
        case .week:
            selection = .week(weekOffset)
        case .month:
            selection = .month(month, year)
        case .year:
            selection = .year(year)
        case .all:
            break
        }
    }
}
