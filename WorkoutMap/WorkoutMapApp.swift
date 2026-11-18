import SwiftUI

@main
struct WorkoutMapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
    }
}
