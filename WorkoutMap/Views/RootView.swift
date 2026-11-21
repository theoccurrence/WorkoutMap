import SwiftUI

struct RootView: View {
    @StateObject private var health = HealthStore()
    @StateObject private var location = LocationProvider()
    @State private var tab: Int = DebugLaunch.startTab
    /// The style the map screen wants its controls in — and with it the tab bar, which is the
    /// app's own and not the screen's. In the light style the selected item is the system's own
    /// blue; the yellow accent is what the dark bar uses.
    @ObservedObject private var controls = ControlAppearance.shared

    var body: some View {
        // The system TabView on purpose: it is what draws the floating Liquid
        // Glass bar (and adapts it to the iPhone Duo's displays).
        TabView(selection: $tab) {
            Tab("Workouts", systemImage: "rectangle.stack.fill", value: 0) {
                WorkoutsListView(health: health)
            }
            // The map tab carries the app's own glyph rather than an SF Symbol. It is a
            // template image, so the bar tints it like the others: white, accent when
            // selected.
            Tab(value: 1) {
                MapTabView(health: health, location: location)
            } label: {
                Label("Map", image: "MapTab")
            }
            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                SettingsView()
            }
        }
        .tint(tab == 1 && controls.isLight ? nil : Palette.accent)
        .task {
            await health.bootstrap()
        }
    }
}
