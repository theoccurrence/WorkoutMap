import SwiftUI
import UIKit

/// The colour each mode — Walk, Run, Ride — is drawn in, and where the user's choice of it
/// lives.
///
/// One colour per mode covers all three places the mode shows itself: the workout routes on the
/// map (and in the snapshots), the position dot and its cone, and the mode's filter button.
/// `@Published` so every screen that reads it redraws the moment a picker moves; the choice is
/// kept in `UserDefaults` under `categoryColor.<mode>`, and removing the key is what a reset
/// does — the default is then what comes back.
final class CategoryColorStore: ObservableObject {
    static let shared = CategoryColorStore()

    /// The `UserDefaults` key prefix; the mode's raw value completes it.
    static let keyPrefix = "categoryColor."

    /// What each mode is drawn in right now, as `0xRRGGBB`.
    @Published private(set) var hexes: [WorkoutCategory: UInt32]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored: [WorkoutCategory: UInt32] = [:]
        for category in WorkoutCategory.allCases {
            stored[category] = Self.storedHex(for: category, in: defaults)
                ?? category.defaultUIColor.hexRGB
        }
        hexes = stored
    }

    static func key(for category: WorkoutCategory) -> String {
        keyPrefix + category.rawValue
    }

    private static func storedHex(for category: WorkoutCategory,
                                  in defaults: UserDefaults) -> UInt32? {
        guard let number = defaults.object(forKey: key(for: category)) as? NSNumber else { return nil }
        return number.uint32Value & 0xFFFFFF
    }

    func hex(for category: WorkoutCategory) -> UInt32 {
        hexes[category] ?? category.defaultUIColor.hexRGB
    }

    func color(for category: WorkoutCategory) -> Color {
        Color(hex: hex(for: category))
    }

    func uiColor(for category: WorkoutCategory) -> UIColor {
        UIColor(hex: hex(for: category))
    }

    /// `#RRGGBB`, as the system colour picker's hex field writes it.
    func hexString(for category: WorkoutCategory) -> String {
        String(format: "#%06X", hex(for: category))
    }

    func setHex(_ hex: UInt32, for category: WorkoutCategory) {
        let value = hex & 0xFFFFFF
        guard value != self.hex(for: category) else { return }
        var next = hexes
        next[category] = value
        hexes = next
        defaults.set(Int(value), forKey: Self.key(for: category))
    }

    /// Takes the colour as the picker hands it over — possibly in a wide gamut — and keeps the
    /// sRGB value the rest of the app draws with.
    func setColor(_ color: Color, for category: WorkoutCategory) {
        setHex(UIColor(color).hexRGB, for: category)
    }

    /// True while every mode is still drawn in the colour it shipped with.
    var isDefault: Bool {
        WorkoutCategory.allCases.allSatisfy { hex(for: $0) == $0.defaultUIColor.hexRGB }
    }

    /// Puts every mode back to its shipped colour.
    func reset() {
        var next = hexes
        for category in WorkoutCategory.allCases {
            defaults.removeObject(forKey: Self.key(for: category))
            next[category] = category.defaultUIColor.hexRGB
        }
        hexes = next
    }
}
