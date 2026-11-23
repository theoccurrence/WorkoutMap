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
                    DebugLaunch.applyJumpOverrides()
                    DebugLaunch.startRotationIfRequested()
                    DebugLaunch.startModeFlipIfRequested()
#if DEBUG
                    // The settings screen's Edit Transfer, without a tap — see `DebugLaunch`.
                    if let path = DebugLaunch.exportEditsPath {
                        let data = (try? RouteEditStore.shared.exportData()) ?? Data()
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                    if let path = DebugLaunch.importEditsPath,
                       let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        _ = try? RouteEditStore.shared.importData(data)
                    }
#endif
                }
        }
    }
}
