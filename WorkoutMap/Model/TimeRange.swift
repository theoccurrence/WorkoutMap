import Foundation

enum RangeKind: String, CaseIterable, Identifiable {
    case week, month, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    /// Where the settings keep the period the map screen opens with.
    static let defaultPeriodKey = "defaultPeriod"

    /// The period to open the map with — the settings' "Default Period". Read when the map
    /// screen is built, so a change applies from the next launch on.
    static var storedDefault: RangeKind {
        UserDefaults.standard.string(forKey: defaultPeriodKey)
            .flatMap(RangeKind.init(rawValue:)) ?? .week
    }
}

enum AppCalendar {
    /// The original app groups weeks Sunday -> Saturday.
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = .current
        return c
    }()

    static func weekStart(offset: Int, from date: Date = Date()) -> Date {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start)
        let sunday = cal.date(byAdding: .day, value: -(weekday - 1), to: start) ?? start
        return cal.date(byAdding: .weekOfYear, value: offset, to: sunday) ?? sunday
    }

    static func weekLabel(offset: Int, from date: Date = Date()) -> String {
        if offset == 0 { return "This Week" }
        if offset == -1 { return "Last Week" }
        let cal = calendar
        let start = weekStart(offset: offset, from: date)
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let y = cal.component(.year, from: start)
        return "\(Fmt.monthShort.string(from: start)) \(cal.component(.day, from: start))\u{2013}\(cal.component(.day, from: end)), \(y)"
    }
}

enum RangeSelection: Hashable {
    case week(Int)
    case month(Int, Int)
    case year(Int)
    case all

    var kind: RangeKind {
        switch self {
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .all: return .all
        }
    }

    var label: String {
        let cal = AppCalendar.calendar
        switch self {
        case .week(let offset):
            return AppCalendar.weekLabel(offset: offset)
        case .month(let month, let year):
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let date = cal.date(from: comps) ?? Date()
            return Fmt.monthYear.string(from: date)
        case .year(let year):
            return "\(year)"
        case .all:
            return "\(RangeSelection.allStartYear) \u{2013} \(RangeSelection.allEndYear)"
        }
    }

    func contains(_ date: Date) -> Bool {
        let cal = AppCalendar.calendar
        switch self {
        case .week(let offset):
            let start = AppCalendar.weekStart(offset: offset)
            guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return true }
            return date >= start && date < end
        case .month(let month, let year):
            let c = cal.dateComponents([.year, .month], from: date)
            return c.year == year && c.month == month
        case .year(let year):
            return cal.component(.year, from: date) == year
        case .all:
            return true
        }
    }

    // Decade window used for the "All" filter label and the year picker.
    static var allStartYear: Int { (minYear / 10) * 10 }
    static var allEndYear: Int { (maxYear / 10) * 10 + 10 }

    static var minYear: Int = Calendar.current.component(.year, from: Date())
    static var maxYear: Int = Calendar.current.component(.year, from: Date())

    static func updateBounds(from workouts: [Workout]) {
        let years = workouts.map { AppCalendar.calendar.component(.year, from: $0.start) }
        guard let lo = years.min(), let hi = years.max() else { return }
        minYear = lo
        maxYear = max(hi, Calendar.current.component(.year, from: Date()))
    }

    static var yearOptions: [Int] {
        Array(allStartYear...allEndYear)
    }

    /// Weeks offered by the picker: from the first workout week up to a few weeks ahead.
    static func weekOptions(from workouts: [Workout]) -> [Int] {
        let cal = AppCalendar.calendar
        let today = Date()
        let earliest = workouts.map(\.start).min() ?? today
        let firstSunday = AppCalendar.weekStart(offset: 0, from: earliest)
        let diff = cal.dateComponents([.weekOfYear], from: firstSunday, to: AppCalendar.weekStart(offset: 0, from: today)).weekOfYear ?? 0
        let firstOffset = min(diff, -3)
        var offsets = Array(firstOffset...(firstOffset + 9))
        if !offsets.contains(0) { offsets.append(0) }
        offsets.sort()
        let maxOffset = max(3, (offsets.max() ?? 3))
        return Array(min(firstOffset, -3)...maxOffset)
    }
}
