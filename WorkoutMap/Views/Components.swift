import SwiftUI

struct CloseCircleButton: View {
    /// The glyph. White on the grey circle — black read as a hole punched in the frosted glass
    /// the newer panels are drawn on, and the circle is dark enough to carry it.
    var glyph: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.closeButton)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(glyph)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The frosted glass the editor's own panel is drawn on.
    ///
    /// **Liquid Glass** (`glassEffect`) rather than a `Material`: over a dark map a material —
    /// even `.ultraThin` — is a grey plate with a blur on it, while the glass keeps its lit edge
    /// and lets the streets read through it. The 16 pt corner is the one the result card carries.
    ///
    /// The map screen's three menus do **not** use this any more: they are cards of their own
    /// (`menuCard()`, with the display's corners), so that a menu and the sheet the range bubble
    /// opens are the same shape. See `MapTabView.menuLayer` for what a menu is, and what it is not:
    /// a real sheet was given a glass panel by the system that no value of `presentationBackground`
    /// removes (measured on iOS 27 — the card keeps its blurred panel whatever that modifier is
    /// told, and only an opaque colour painted over it hides it), and it is the full width of the
    /// window, so on the Duo it lies over the screen's rail.
    func glassPanel() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The card a menu of the map screen is drawn on: the same Liquid Glass, on **the display's own
    /// corners**.
    ///
    /// `ConcentricRectangle` asks the container for its corner shape instead of being told a
    /// number, which is the whole of why a menu now matches the sheet the range bubble opens: that
    /// sheet is a system card, and its corners are the display's, inset by the sheet's own margin.
    /// Concentric then has to resolve to the same thing here — the card sits in the map screen with
    /// the same margin from the same display — so the two are the same shape, on every display the
    /// app runs on. Where that resolution is measured to work (the Pro Max: the detail card's own
    /// corners walk ~90 px, about 30 pt) the two agree; on the Duo's folded cover panel it resolves
    /// below the floor, so there the floor — the 8 pt the system's own card carries on that panel's
    /// sharp side — is what decides (the README's numbers have both).
    ///
    /// The minimum is `Metrics.menuCardRadius`: the radius the system's own sheet card measured at on
    /// the folded Duo, so the card's corners match the sheet's sharp side there.
    func menuCard() -> some View {
        glassEffect(.regular,
                    in: ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.menuCardRadius))))
    }

    /// The margin a menu card keeps from the display's own edges — the same on all four sides, and
    /// measured from the display rather than from the safe area, so the card reaches over the band
    /// the tab bar and the Duo's rail register live in instead of stopping short of it. The bottom
    /// one is what makes it a card rather than a sheet that runs off the edge.
    ///
    /// It is the margin the detail sheet's card keeps (`Metrics.menuCardInset`, measured), so a menu
    /// and that card sit in the same place on the same display.
    func menuCardInsets() -> some View {
        padding(.leading, Metrics.menuCardInset)
            .padding(.trailing, Metrics.menuCardInset)
            .padding(.bottom, Metrics.menuCardInset)
    }
}

/// The hairline between two rows of a settings card: one physical pixel, inset to where the row's
/// text starts, in the faint white the cards use.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(height: 1 / displayScale)
            .padding(.leading, 56)
    }
}

/// Full width yellow confirm button (sheet Done / export Save).
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 47
    /// Measured from the original app: both confirm buttons use a 10 pt radius.
    var radius: CGFloat = 10
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
