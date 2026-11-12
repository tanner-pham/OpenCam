import SwiftUI

/// Folded and horizontal. A 16:9 picture fills the width; readouts live in the bars above and below it.
struct FoldedHorizontalView: View {
    let model: CameraModel
    let size: CGSize
    /// The system bars' top and bottom insets the controls keep clear of; zero on the folded phone.
    var insets = EdgeInsets()
    /// The side of the system's vertical bar; the readouts keep their wider inset for the screen's corner on the other side.
    var stripEdge: HorizontalEdge?

    var body: some View {
        VStack(spacing: 0) {
            TopReadoutBar(model: model, stripEdge: stripEdge)
                .frame(height: Theme.Size.topBar)
            ViewfinderArea(phase: model.phase, look: model.viewfinderLook, onRetry: model.isCameraStopped ? { model.retryCamera() } : nil)
                .frame(width: size.width, height: size.width * 9 / 16)
                .clipped()
                .overlay(alignment: .topTrailing) { DroppedFramesBadge(model: model).padding(Theme.Space.s) }
            BottomBar(model: model, stripEdge: stripEdge)
                .frame(maxHeight: .infinity)
        }
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
    }
}
