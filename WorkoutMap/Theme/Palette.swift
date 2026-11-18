import SwiftUI

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
    static let dotRing       = Color(hex: 0xC7C7CC)
    static let closeButton   = Color(hex: 0xA4A4A4)
    static let pickerGlass   = Color(hex: 0x2C2C2F)
}
