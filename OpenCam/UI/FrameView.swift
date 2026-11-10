import SwiftUI

/// The camera's frames drawn through the selected look. Present only while a look is shown; removing it turns the
/// pipeline's look off, which empties its slot.
struct FrameView: UIViewRepresentable {
    let frames: FramePipeline
    let look: CameraLook
    let onFirstFrame: () -> Void

    func makeUIView(context: Context) -> FrameMetalView {
        frames.setLook(look.adjustments)
        return FrameMetalView(frames: frames, onFirstFrame: onFirstFrame)
    }

    /// The pipeline ignores a look it already has, so only a changed look reaches it.
    func updateUIView(_ uiView: FrameMetalView, context: Context) {
        frames.setLook(look.adjustments)
    }

    static func dismantleUIView(_ uiView: FrameMetalView, coordinator: ()) {
        uiView.frames.setLook(nil)
    }
}
