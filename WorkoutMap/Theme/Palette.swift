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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1)
    }

    /// The colour as `0xRRGGBB`, with each component clamped and rounded. A colour the picker
    /// hands back in a wide gamut is reduced to the sRGB byte it is closest to.
    var hexRGB: UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(max(component, 0), 1) * 255).rounded())
        }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// Exact colours measured from the original app.
enum Palette {
    static let accent      = Color(hex: 0xFFC703)

    /// Toolbar / pills / floating buttons.
    static let surface     = Color(hex: 0x393939)
    /// List cards, stat cards.
    static let card        = Color(hex: 0x1C1C1E)
    static let background  = Color.black

    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary  = Color(hex: 0x6C6C70)
    /// The map's range bubble label — measured grey, never white.
    static let rangeLabel    = Color(hex: 0xA4A4A4)
    /// The bubble's label on a map drawn light, as Maps draws it — the pill itself is glass now.
    static let rangeLabelLight = Color(hex: 0x3C3C43)
    static let dotRing       = Color(hex: 0xC7C7CC)
    /// The ring around the chosen map style in the "Map Modes" sheet — the dark-mode system
    /// blue, the one Apple Maps' own panel uses.
    static let modeSelection = Color(hex: 0x0A84FF)
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

/// How a GPS jump is drawn when the setting asks for it: the grey the Fitness app dots across
/// ground the workout never measured.
///
/// A jump is a row of **circles**, and both the circle and the gap between two of them are
/// measured against the width the route itself is drawn at — a jump on a thicker line gets
/// bigger dots rather than the same dots on a heavier stroke. A dot is stroked as a
/// zero-length dash with a round cap, so the cap *is* the circle and its diameter is the line
/// width.
enum RouteJump {
    /// The grey a leg the distance rule catches is drawn in *until the user picks another tone*
    /// (`JumpColorStore`).
    static let distanceTone = UIColor(red: 174.0 / 255, green: 174.0 / 255, blue: 178.0 / 255, alpha: 1)
    /// The tone a leg the speed rule catches ships in — the system red, so a fast leg never reads
    /// as the route's own colour, whatever the user has set that to. It is the default of
    /// `JumpColorStore` for that rule.
    static let speedTone = UIColor(red: 1, green: 69.0 / 255, blue: 58.0 / 255, alpha: 1)

    /// A dot is this share of the route's own width — thinner than the route, so the ground
    /// that *was* walked reads as the solid line and the jump as a trail beside it.
    static let dotScale: CGFloat = 0.65
    /// Centre-to-centre spacing of two dots, in dot diameters.
    static let spacingScale: CGFloat = 2.4

    /// The diameter of one dot on a route drawn `routeWidth` wide.
    static func dotDiameter(routeWidth: CGFloat) -> CGFloat {
        max(1, routeWidth * dotScale)
    }

    /// The dash pattern that draws those dots: a zero-length dash with a round cap is one
    /// circle, and the second length is the gap that sets how far apart they sit.
    static func dotDash(routeWidth: CGFloat) -> [CGFloat] {
        [0.01, dotDiameter(routeWidth: routeWidth) * spacingScale]
    }
}
