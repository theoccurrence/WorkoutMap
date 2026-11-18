import SwiftUI

/// The olive gradient + grain backdrop of the Workouts and Settings screens.
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            Image("AppBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}
