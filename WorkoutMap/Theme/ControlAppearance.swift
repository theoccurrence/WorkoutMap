import SwiftUI

/// The style the app's own controls are drawn in — the tab bar, from the map screen's point of
/// view.
///
/// The map decides it: a map drawn light gets light controls, and `legacy` — the grey map the app
/// shipped with — never does. The map screen writes it, and the tab bar is the one control that
/// is the app's rather than the screen's, so it needs telling: in the light style its selected
/// item is the system's own blue instead of the app's yellow. The app's own design is dark, so
/// this is only true while the map screen is the one in front (`RootView`).
final class ControlAppearance: ObservableObject {
    static let shared = ControlAppearance()

    /// Whether the controls are in the light style.
    @Published private(set) var isLight = false

    func setLight(_ light: Bool) {
        guard light != isLight else { return }
        withAnimation(.easeInOut(duration: 0.35)) { isLight = light }
    }
}
