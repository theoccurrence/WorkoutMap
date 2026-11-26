import SwiftUI
import UIKit

/// The tone each jump rule draws its legs in, and where the user's choice of it lives.
///
/// A leg a rule catches is grey (distance) or orange (speed) until the user picks another tone —
/// the way `CategoryColorStore` holds a mode's colour. The tone belongs to the **rule**, not to
/// the way it is drawn, so a leg reads as that rule's whether the rule draws it dotted or solid.
/// `@Published` so every screen that reads it redraws the moment a picker moves; the choice is
/// kept in `UserDefaults` under `jumpColor.<rule>`, and removing the key is what a reset does —
/// the shipped tone is then what comes back.
final class JumpColorStore: ObservableObject {
    static let shared = JumpColorStore()

    /// The `UserDefaults` key prefix; the rule's raw value completes it.
    static let keyPrefix = "jumpColor."

    /// What each rule draws in right now.
    @Published private(set) var tones: JumpTones

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tones = JumpTones(distance: Self.storedHex(for: .distance, in: defaults)
                              .map { UIColor(hex: $0) } ?? JumpTones.standard.distance,
                          speed: Self.storedHex(for: .speed, in: defaults)
                              .map { UIColor(hex: $0) } ?? JumpTones.standard.speed)
    }

    static func key(for kind: JumpKind) -> String {
        keyPrefix + kind.rawValue
    }

    private static func storedHex(for kind: JumpKind, in defaults: UserDefaults) -> UInt32? {
        guard let number = defaults.object(forKey: key(for: kind)) as? NSNumber else { return nil }
        return number.uint32Value & 0xFFFFFF
    }

    func hex(for kind: JumpKind) -> UInt32 {
        tones.uiColor(for: kind).hexRGB
    }

    func color(for kind: JumpKind) -> Color {
        Color(hex: hex(for: kind))
    }

    /// `#RRGGBB`, as the system colour picker's hex field writes it.
    func hexString(for kind: JumpKind) -> String {
        String(format: "#%06X", hex(for: kind))
    }

    func setHex(_ hex: UInt32, for kind: JumpKind) {
        let value = hex & 0xFFFFFF
        guard value != self.hex(for: kind) else { return }
        tones = tones.setting(UIColor(hex: value), for: kind)
        defaults.set(Int(value), forKey: Self.key(for: kind))
    }

    /// Takes the colour as the picker hands it over — possibly in a wide gamut — and keeps the
    /// sRGB value the rest of the app draws with.
    func setColor(_ color: Color, for kind: JumpKind) {
        setHex(UIColor(color).hexRGB, for: kind)
    }

    /// True while both rules still draw in the tone they shipped with.
    var isDefault: Bool { tones == .standard }

    /// Puts both rules back to their shipped tone.
    func reset() {
        for kind in [JumpKind.distance, .speed] {
            defaults.removeObject(forKey: Self.key(for: kind))
        }
        tones = .standard
    }
}

/// The two tones together, as everything that draws a jump leg takes them.
struct JumpTones: Equatable {
    /// What a leg the distance rule catches is drawn in.
    var distance: UIColor
    /// What a leg the speed rule catches is drawn in.
    var speed: UIColor

    /// What a fresh install draws with: the grey measured from the original app, and the orange the
    /// speed rule now ships in.
    static let standard = JumpTones(distance: RouteJump.distanceTone, speed: RouteJump.speedTone)

    func uiColor(for kind: JumpKind) -> UIColor {
        switch kind {
        case .distance: return distance
        case .speed: return speed
        }
    }

    func setting(_ color: UIColor, for kind: JumpKind) -> JumpTones {
        switch kind {
        case .distance: return JumpTones(distance: color, speed: speed)
        case .speed: return JumpTones(distance: distance, speed: color)
        }
    }

    /// A short form for caches that have to be rebuilt when a tone changes — the thumbnails.
    var key: String {
        "\(distance.hexRGB)-\(speed.hexRGB)"
    }
}
