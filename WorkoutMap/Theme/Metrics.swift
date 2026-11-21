import SwiftUI

/// Geometry measured from the original app (iPhone 17 Pro Max, 440 x 956 pt).
enum Metrics {
    static let screenInset: CGFloat = 18          // list cards, sheet button
    static let contentInset: CGFloat = 20         // settings cards, large title
    static let cardHeight: CGFloat = 100
    static let cardGap: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let controlHeight: CGFloat = 42        // range bubble
    static let pillGap: CGFloat = 12
    /// The explorer button stands above the Walk / Run / Ride filters with twice the gap
    /// between the three of them, so it reads as a group of its own.
    static let exploreGap: CGFloat = pillGap * 2
    static let statCardRadius: CGFloat = 12
    /// The side inset the system reserves for its own rail on a screen whose chrome lives
    /// in a vertical bar (84 pt on the iPhone Duo, 62 pt on a notched iPhone held sideways,
    /// so 70 tells them apart). `usesVerticalControls` switches the map screen to that
    /// layout once the inset crosses this: the toolbar actions become real toolbar items
    /// in the system's own vertical bar beside the tab bar, and the filters move to the
    /// opposite side.
    static let railInset: CGFloat = 70
    /// The filters line up with the floating tab bar's own bottom edge, measured from the
    /// bar. This is the inset to the line it roughly sits on, used until that lands.
    static let filterInsetBottomBar: CGFloat = 8
    /// Down a side the filters sit on the tab bar's bottom edge; this is the measured
    /// offset from the screen's bottom edge in the folded portrait, used when the bar
    /// cannot be located reliably (a rotation can leave a parked copy of it in the window).
    static let filterInsetRailPortrait: CGFloat = 23
    /// The folded landscape keeps to the same edge, 4 px higher — 1.33 pt at the 3x the
    /// offsets are measured at. Measured on the two bottom edges: the rail's platter ends
    /// at 1325 px and the filter column's last circle reached 1328, so the circles come up
    /// by those 4 px to sit exactly level with the platter.
    static let filterInsetFoldedLandscape: CGFloat = 23 + 4.0 / 3.0
    /// The map screen's own toolbar — the screens the system gives no side rail. Sized like
    /// the system rail's buttons: a 44 pt target with a ~21 pt glyph.
    static let toolbarButtonSize: CGFloat = 44
    static let toolbarIconSize: CGFloat = 21
    static let routeWidth: CGFloat = 2.9
    /// Card map thumbnail: the last ~100 pt of a list card (measured at 75.1 % of 403.7 pt).
    static let thumbnailWidth: CGFloat = 100.3
}
