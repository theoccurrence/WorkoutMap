import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

/// Exact colours measured from the original app.
enum Palette {
    static let accent      = Color(hex: 0xFFC703)
    static let orange      = Color(hex: 0xEB7D14)
    static let green       = Color(hex: 0x0BA958)

    /// Toolbar / pills / floating buttons.
    static let surface     = Color(hex: 0x393939)
    /// List cards, stat cards, sheet background.
    static let card        = Color(hex: 0x1C1C1E)
    static let sheetCard   = Color(hex: 0x1C1C1E)
    static let background  = Color.black

    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary  = Color(hex: 0x6C6C70)
    /// The map's range bubble label — measured grey, never white.
    static let rangeLabel    = Color(hex: 0xA4A4A4)
    /// The same bubble on a map drawn light: a light pill with a dark label, as Maps draws it.
    static let surfaceLight  = Color(hex: 0xF2F2F7)
    static let rangeLabelLight = Color(hex: 0x3C3C43)
    static let dotRing       = Color(hex: 0xC7C7CC)
    static let closeButton   = Color(hex: 0xA4A4A4)
    /// The ring around the chosen map style in the "Map Modes" sheet — the dark-mode system
    /// blue, the one Apple Maps' own panel uses.
    static let modeSelection = Color(hex: 0x0A84FF)
    static let pickerGlass   = Color(hex: 0x2C2C2F)
    /// The destination pin the explorer drops, and its row in the sheet — the system red Maps
    /// drops its own pin in.
    static let pin           = Color(hex: 0xFF3B30)
}

/// The blue a planned route is drawn in, as Apple Maps draws its own: a bright blue with a
/// darker blue casing for the selected route, and the same blue washed out for the alternates.
enum RouteBlue {
    static let primary   = Color(hex: 0x0A84FF)
    static let alternate = Color(hex: 0x0A84FF).opacity(0.45)

    static let uiPrimary   = UIColor(red: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 1)
    static let uiAlternate = UIColor(red: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 0.45)
    static let uiCasing    = UIColor(red: 3.0 / 255, green: 61.0 / 255, blue: 138.0 / 255, alpha: 1)
}
