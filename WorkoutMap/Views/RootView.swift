import SwiftUI

struct RootView: View {
    @StateObject private var health = HealthStore()
    @StateObject private var location = LocationProvider()
    @State private var tab: Int = DebugLaunch.startTab

    var body: some View {
        // The system TabView on purpose: it is what draws the floating Liquid
        // Glass bar (and adapts it to the iPhone Duo's displays).
        TabView(selection: $tab) {
            Tab("Workouts", systemImage: "rectangle.stack.fill", value: 0) {
                WorkoutsListView(health: health)
            }
            Tab("Map", systemImage: "map.fill", value: 1) {
                MapTabView(health: health, location: location)
            }
            Tab("Setting", systemImage: "gearshape.fill", value: 2) {
                SettingsView()
            }
        }
        .tint(Palette.accent)
        .task {
            await health.bootstrap()
        }
    }
}
