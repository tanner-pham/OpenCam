import SwiftUI

/// Closes the open slider.
struct ControlCloseButton: View {
    let model: CameraModel

    var body: some View {
        Button { model.closeControl() } label: {
            Image(systemName: "xmark")
                .frame(minWidth: Theme.Size.minTarget, minHeight: Theme.Size.minTarget)
        }
        .accessibilityLabel("Close slider")
    }
}
