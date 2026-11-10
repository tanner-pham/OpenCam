import SwiftUI

/// The "No camera in Simulator" capsule, shown over the stand-in picture with or without a look.
struct StandInCaption: View {
    /// Extra top inset for when readouts float over the picture.
    var topInset: CGFloat = 0

    var body: some View {
        Text("No camera in Simulator")
            .font(.caption2)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(Theme.Space.s)
            .padding(.top, topInset)
    }
}
