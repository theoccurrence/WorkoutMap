import SwiftUI

struct CloseCircleButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.closeButton)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
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
