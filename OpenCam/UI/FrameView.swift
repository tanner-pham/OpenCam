import SwiftUI

/// The camera's frames drawn through the selected look. Present only while a look is shown. Each view sets the look under
/// its own token, so a view taken down after its replacement was made (a layout change) cannot switch the look off.
struct FrameView: UIViewRepresentable {
    let frames: FramePipeline
    let look: CameraLook
    let onFirstFrame: () -> Void

    /// The view's owner token for the pipeline's look.
    func makeCoordinator() -> UUID { UUID() }

    func makeUIView(context: Context) -> FrameMetalView {
        frames.setLook(look.adjustments, owner: context.coordinator)
        return FrameMetalView(frames: frames, onFirstFrame: onFirstFrame)
    }

    /// A changed look reaches the pipeline only while this view is still its owner, so an old view updated during a layout
    /// change cannot take the look back from its replacement.
    func updateUIView(_ uiView: FrameMetalView, context: Context) {
        frames.changeLook(look.adjustments, owner: context.coordinator)
    }

    static func dismantleUIView(_ uiView: FrameMetalView, coordinator: UUID) {
        uiView.frames.clearLook(owner: coordinator)
    }
}
