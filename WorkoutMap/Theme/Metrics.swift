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
    /// The gap between the detail screen's stat cards, both ways. It was 20 across and 12 down while
    /// the grid was fixed at two columns; one gap for both axes is what lets the same six cards be laid
    /// out three rows by two or two rows by three without the block changing size.
    static let statCardGap: CGFloat = 12
    /// The margin a menu card of the map screen keeps from the display's own edges — the same on
    /// all four sides, so the card reaches over the band the tab bar and the Duo's rail register
    /// live in, and the bottom one ends it above the display's bottom edge instead of running off
    /// it. Measured off the sheet the range bubble opens (the card the user wanted the menus to
    /// look like): 24 px at 3x = 8 pt, on the Pro Max and on both of the Duo's displays.
    static let menuCardInset: CGFloat = 8
    /// The smallest corner a menu card is drawn with: the radius the system's own sheet card carries
    /// on the folded Duo's *sharp* side (measured: 24 px of arc at 3x, an 8 pt radius, on a card inset
    /// 8 pt from the display). The card asks `ConcentricRectangle` for the container's radius and this
    /// is the floor under that answer, so the card never comes out with square corners: measured on the
    /// Pro Max the resolution sees the display (the detail card's own corners there walk ~90 px, about
    /// 30 pt); on the Duo's cover panel it resolves below this floor, and the floor is what decides —
    /// which is why it is the measured 8 pt the system's own card uses there and not a rounder guess.
    /// A floor *above* that answer is what a 16 pt one cost: every corner of the folded Duo's card came
    /// out 16 pt, against 8 pt on its sharp side and 19 pt on its rounded one.
    static let menuCardRadius: CGFloat = 8
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
