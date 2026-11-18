import Foundation

enum Fmt {
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()

    static let detailDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy EEE h:mm a"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let monthShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f
    }()

    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func distanceValue(_ meters: Double) -> (value: String, unit: String) {
        if meters < 1000 { return ("\(Int(meters.rounded()))", "m") }
        return (String(format: "%.2f", meters / 1000), "km")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    static func elevation(_ meters: Double) -> String { "\(Int(meters.rounded()))" }

    static func caloriesValue(_ kcal: Double) -> String {
        if kcal >= 1000 { return String(format: "%.2fk", kcal / 1000) }
        return String(format: "%.2f", kcal)
    }

    static func pace(_ seconds: TimeInterval, meters: Double) -> String {
        guard meters > 1 else { return "--\'--\"" }
        let sPerKm = seconds / (meters / 1000)
        let m = Int(sPerKm) / 60
        let s = Int(sPerKm) % 60
        return String(format: "%d\'%02d\"", m, s)
    }

    static func heartRate(_ bpm: Double) -> String { "\(Int(bpm.rounded()))" }

    static func temperature(_ celsius: Double) -> String { String(format: "%.1f\u{00B0}C", celsius) }

    static func humidity(_ percent: Double) -> String { "\(Int(percent.rounded()))%" }
}
