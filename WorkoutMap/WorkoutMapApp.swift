import SwiftUI

@main
struct WorkoutMapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .background(Color.black)
                .task {
                    for (category, hex) in DebugLaunch.modeColors {
                        CategoryColorStore.shared.setHex(hex, for: category)
                    }
                    if DebugLaunch.resetModeColors { CategoryColorStore.shared.reset() }
                    DebugLaunch.startRotationIfRequested()
                    DebugLaunch.startModeFlipIfRequested()
                }
        }
    }
}
