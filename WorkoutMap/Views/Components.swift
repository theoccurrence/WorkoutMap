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
    /// The frosted glass every panel of the map screen is drawn on.
    ///
    /// **Liquid Glass** (`glassEffect`) rather than a `Material`: over a dark map a material —
    /// even `.ultraThin` — is a grey plate with a blur on it, while the glass keeps its lit edge
    /// and lets the streets read through it. The shape is the panel's own, so the bottom corners
    /// stay square where the sheet meets the screen edge.
    ///
    /// `presentationBackgroundInteraction(.enabled)` because the system otherwise dims whatever is
    /// behind the sheet, and glass over something dimmed has nothing left to be glass over.
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: cornerRadius,
                                                         bottomLeadingRadius: 0,
                                                         bottomTrailingRadius: 0,
                                                         topTrailingRadius: cornerRadius,
                                                         style: .continuous))
            .presentationBackground(.clear)
            .presentationBackgroundInteraction(.enabled)
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
