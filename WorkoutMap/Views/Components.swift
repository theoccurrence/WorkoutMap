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
    /// The frosted glass every panel of the map screen is drawn on — the range bubble, the
    /// explorer's result card and the screen's three menus, all of which are drawn **in the map
    /// screen itself**.
    ///
    /// **Liquid Glass** (`glassEffect`) rather than a `Material`: over a dark map a material —
    /// even `.ultraThin` — is a grey plate with a blur on it, while the glass keeps its lit edge
    /// and lets the streets read through it. The 16 pt corner is the one the result card carries.
    ///
    /// A menu is drawn here rather than presented as a sheet on purpose. A half-height sheet is
    /// given a glass panel **by the system** — Apple's own note on adopting Liquid Glass: "half
    /// sheets are inset from the edge of the display", with the glass the design gives them — and
    /// no value of `presentationBackground` removes it (measured on iOS 27: the card keeps its
    /// blurred panel whatever that modifier is told, and only an opaque colour painted over it
    /// hides it). The card is also the full width of the window, so on the Duo it lies over the
    /// screen's rail — the toolbar and the tab registers — and no panel drawn inside it can stop
    /// short of that. Drawn in the map screen, a menu keeps the insets the range bubble and the
    /// card keep (`MapTabView.menuPanel`) and never touches the screen's chrome.
    func glassPanel() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
