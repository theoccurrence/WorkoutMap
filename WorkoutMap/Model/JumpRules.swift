import Foundation

/// How the two softer jump rules are set: what counts as a jump, and how it is drawn.
///
/// The app has always told a jump apart with three thresholds **at once** — the leg has to cover
/// more than 25 m *and* beat 162 km/h (or, with no usable timestamp, cover 300 m) — and that
/// strict rule stays exactly as it was. It is never drawn any more (`WorkoutRoute.drawing`): the
/// legs it catches are the ones the receiver invented, and the map leaves them out.
///
/// These two rules are the ones the settings expose, each on its own:
///
/// * a leg longer than `distanceThreshold` is a **distance** leg,
/// * a leg that covers `speedMinimumDistance` and is faster than `speedThreshold` is a **speed**
///   leg.
///
/// A leg that trips both is drawn as a speed leg — the faster reading is the more telling one —
/// and a leg the strict rule catches is drawn as neither.
struct JumpRules: Equatable {
    /// The ground a leg has to cover before its speed is judged at all, in metres.
    ///
    /// A leg's speed is only as good as the two timestamps behind it, and a receiver's timestamps
    /// are rounded: two fixes a metre apart, a hundredth of a second apart, imply 100 m/s. That is
    /// a bad timestamp, not a jump, and the app has no business drawing a lone dot for a fix the
    /// user was standing on. Twenty-five metres is what the strict rule already asks for; the
    /// speed rule is left at a tenth of it, so a leg it catches is still ground the user covered.
    static let speedMinimumDistance: Double = 10  // m

    var distanceStyle: RouteJumpStyle
    /// The distance, in metres, past which a leg counts as a jump.
    var distanceThreshold: Double
    var speedStyle: RouteJumpStyle
    /// The speed, in km/h, past which a leg counts as a jump.
    var speedThreshold: Double

    /// What a fresh install starts with: the strict rule's own numbers, with the distance rule
    /// showing what it finds and the speed rule leaving it out. The strict rule hides the big
    /// jumps either way, so this is the shape of the app before the rules were split.
    static let standard = JumpRules(distanceStyle: .dotted,
                                    distanceThreshold: JumpSettings.distanceThresholdDefault,
                                    speedStyle: .hidden,
                                    speedThreshold: JumpSettings.speedThresholdDefault)

    var speedThresholdMetersPerSecond: Double { speedThreshold / 3.6 }

    func style(for kind: JumpKind) -> RouteJumpStyle {
        switch kind {
        case .distance: return distanceStyle
        case .speed: return speedStyle
        }
    }

    /// A short form for caches that have to be rebuilt when the rules change — the thumbnails.
    var key: String {
        "\(distanceStyle.rawValue)-\(Int(distanceThreshold))-\(speedStyle.rawValue)-\(Int(speedThreshold))"
    }
}

/// Where the settings keep the two rules, and how far their sliders reach.
enum JumpSettings {
    static let distanceStyleKey = "jumpDistanceStyle"
    static let distanceThresholdKey = "jumpDistanceThreshold"
    static let speedStyleKey = "jumpSpeedStyle"
    static let speedThresholdKey = "jumpSpeedThreshold"

    /// The strict rule's own distance, in metres (25 m).
    static let distanceThresholdDefault: Double = 25
    /// The strict rule's own speed, in km/h (45 m/s = 162 km/h).
    static let speedThresholdDefault: Double = 162

    static let distanceRange: ClosedRange<Double> = 5...100
    static let speedRange: ClosedRange<Double> = 20...200
    /// The distance slider moves in whole 5 m steps; the speed one in single km/h.
    static let distanceStep: Double = 5
    static let speedStep: Double = 1
}

/// What a leg was caught by.
enum JumpKind: String {
    /// Longer than the distance rule's threshold.
    case distance
    /// Faster than the speed rule's threshold.
    case speed
}
