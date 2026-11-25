import SwiftUI

/// Geometry measured from the original app (iPhone 17 Pro Max, 440 x 956 pt).
enum Metrics {
    static let screenInset: CGFloat = 18          // list cards, sheet button
    /// The inset that puts a floating control's **centre** on the status cluster's own centre — the
    /// whole of why the workout's rail reads as aligned with the icons above it instead of merely near
    /// them. Measured on the folded Duo's cover panel: its cluster is a capsule, and the clock and the
    /// radio arc (the two elements a rail is read against) are centred **48 pt** from the display's
    /// trailing edge, so a 48.5 pt disc wants 48 − 24.25 = **23.75**.
    /// A notched iPhone's cluster sits further in and the app's own `screenInset` (18, i.e. a centre
    /// 42.25 pt in) is within a few points of it (~45), so that side keeps the app's own column.
    ///
    /// The panel's capsule is *not* uniformly centred, and the first reading of it was wrong because of
    /// that: its battery dots sit at 37.8 pt from the trailing edge while the clock and the radio arc —
    /// the two elements a rail is read against — sit at **48.0**, so the inset is 48 − 24.25 = **23.75**.
    /// (An earlier value of 13.25 put the rail 10.5 pt *right* of the clock: the user's screenshot.)
    static let statusColumnInsetFolded: CGFloat = 23.75
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
    /// The corner a menu card is drawn with where the display's own corner is not what decides.
    ///
    /// The card asks `ConcentricRectangle` for a **dynamic** radius — `UICornerConfiguration`'s
    /// `containerConcentricRadius`, documented as letting *each corner* resolve to its own answer from
    /// the geometry of the view and its container — and that is what this value scales down where the
    /// display's own corner is willing to answer: a corner resting on a display edge is drawn with the
    /// display's radius (round on a round side, nearly square on the folded Duo's cover panel, which is
    /// what the display's own corner is there), and a corner out in the open is drawn with **this** —
    /// the strongly rounded look every floating card has. Out in the open no geometry is left to ask —
    /// the container answers nothing at all there — which is why this one corner is a number.
    ///
    /// Measured off Apple Maps' own card on the same 466 pt display, corner against corner with this
    /// app's: both of the Maps card's top corners are circles of 120.5 px = 40.2 pt, while this app's
    /// read 96.4 px = 32.1 pt at the 32 it carried before — 8 pt tighter than the card it is meant to
    /// match. The older reading of that same corner agrees with 40 from the other end: six pixels down
    /// from the card's top edge the Maps boundary is 86 px in, a radius of ~41 pt (against 49 px, a
    /// radius of 25 pt, for this app's card at the 26 pt it had then). The change is blended over
    /// `menuCardBlend` points of approach, so it is a slow one rather than a jump (`menuCardShape`).
    static let menuCardRadius: CGFloat = 40
    /// The smallest radius a card's corner is ever drawn with, however square the display's own corner
    /// is there: the radius the system's own cards carry on the folded Duo's *sharp* side (measured off
    /// the sheet's card on that panel: 24 px of arc at 3x, an 8 pt radius, on a card inset 8 pt from the
    /// display). Without it a card's corner would come out *square* where that display is nearly square
    /// — measured: the card's bottom-left corner was the straight edge itself, on every row — and a card
    /// wants to keep the small rounding the display's own cards have there.
    static let menuCardFloor: CGFloat = 8
    /// How far a card's corner has to come from a display corner before it is drawn with the default
    /// radius above rather than with the display's own: the shape is blended over this many points of
    /// approach (`menuCardShape`), which is the slow change the system's own sheets show as they are
    /// dragged towards one.
    static let menuCardBlend: CGFloat = 64
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
    /// Where a card's own close cross sits **inside the card** — the same inset on the top and on the
    /// trailing side, which is what makes a corner control read as placed rather than nudged.
    ///
    /// Equal insets are what Apple Maps' own cards do: measured on the Duo's cover panel, its *Map
    /// Modes* card carries a 48.7 pt circle 16 pt from the card's top edge and 14 pt from its side,
    /// where this app's read 16 and **9**. The trailing inset used to put the cross's centre on the
    /// column the map screen's own toolbar keeps (`screenInset` + half a button in from the display,
    /// less the card's `menuCardInset`), which a 44 pt target made 10 and a 48.5 pt one could not
    /// hold; a card keeps this on every side instead, and the rail's own column is the rail's business.
    ///
    /// It also keeps the circle inside the card's shape: the card's corner radius out in the open is
    /// `menuCardRadius` (40 pt), so its arc is centred 40 pt in from both edges — and this inset puts
    /// the 48.5 pt circle's centre at 16 + 24.25 = 40.25 pt, on that centre, leaving its edge
    /// **15.4 pt clear** of the arc.
    static let menuCardCrossInset: CGFloat = 16
    /// The room a menu card's header takes: the close cross, and the room under it.
    static let menuHeaderHeight: CGFloat = toolbarButtonSize
    /// The **close cross's** own glyph size — the one glyph that needs a size of its own.
    ///
    /// A bare `xmark` is the smallest box of any symbol the app draws: at the body font its ink is
    /// **13 pt**, where Apple Maps' own *Map Modes* card draws ~**16.8** (measured at 3× on the Duo's
    /// cover panel: 50 × 51 px against this app's 39 × 39). The glass pads the *label's* box
    /// (`glassButtonLabel`) and never the glyph, so the cross can take a size of its own without moving
    /// the disc: 22 pt of font puts the ink back at ~16.8 pt inside the same 48.5 pt circle.
    static let closeGlyphSize: CGFloat = 22
    /// The same cross for the **medium** button (`PlannedRouteBar`'s, 32.5 pt): the glyph scales with
    /// the disc, so a medium button carries a small x — 22 × 32.5 / 48.5, i.e. **15 pt** of font,
    /// ~11.5 pt of ink against the large one's 16.8.
    static let closeGlyphSizeMedium: CGFloat = 15
    /// The **label** box inside a round glass button (`GlassCircleButton`) — the one number that
    /// decides how big a disc the app's round glass buttons are.
    ///
    /// The glass pads whatever label it is handed and adds no size of its own, so the label's box *is*
    /// the disc, less the system's padding around it. That padding is not documented and was measured
    /// on the Pro Max: **15 pt per side at `.controlSize(.large)`**, 7 at `.regular`. A bare SF Symbol
    /// is a different box for every symbol — measured at `.large`: `chevron.left` 42.7 × 47.3 pt,
    /// `xmark` 47.3 × 46, `square.and.arrow.up` 49 × 52.7, `eraser` 50.7 × 50, `ellipsis` 48.3 × 36 —
    /// so it made the workout card's three actions three sizes, and not square ones. This box plus the
    /// 30 pt is what every round button in the app comes out at: **48.5 pt = 145.5 px at 3×**, the size
    /// the polished third-party crosses measure, and still 4.5 pt over the 44 pt the Human Interface
    /// Guidelines ask a hit region to be. `.controlSize` (`mini` … `extraLarge`) is the only size the
    /// system offers and Apple publishes no points for any of them, so this box is the only continuous
    /// lever there is.
    ///
    /// A **capsule's** label is pinned to the same box (`PlannedRouteBar`'s *Go* and *Stop*, the editor's
    /// *Done*): the system pads a capsule exactly as it pads a circle — 15 pt a side at `.large`, 7 at
    /// `.regular` — and a bare text label brings its own line box (20.3 pt at the body font), which would
    /// make the button taller than the disc beside it. The box is a *height* there; the width still hugs
    /// the text. The plan-route pair carries the medium size (`.regular`, 32.5 pt); the editor's *Done*
    /// the app's default (`.large`, 48.5 pt), where it stands beside the editor's own close cross.
    static let glassButtonLabel: CGFloat = 18.5
    static let routeWidth: CGFloat = 2.9
    /// Card map thumbnail: the last ~100 pt of a list card (measured at 75.1 % of 403.7 pt).
    static let thumbnailWidth: CGFloat = 100.3
}
