import SwiftUI

extension EnvironmentValues {
    /// The live session's preview source; nil in the Simulator.
    @Entry var previewSource: PreviewSource?
}

/// The picture area: the live preview when ready, the stand-in in the Simulator, what is wrong in words when there is no camera picture.
/// With a look on the device, its frames are drawn over the preview. Until the first frame is drawn the frame view is
/// transparent and the plain preview shows; from then on the frames show and the preview is hidden but stays in place (its
/// rotation coordinator turns the frames). `isFrameDrawn` goes back to false when the frame view is removed: when the look
/// turns off, when its frames fall back, and during a sweep, so the next look-on starts from the plain preview again.
/// Turning a look on or off never rebuilds the preview.
struct ViewfinderArea: View {
    let phase: CameraPhase
    var look: CameraLook? = nil
    var captionTopInset: CGFloat = 0

    @Environment(\.previewSource) private var previewSource
    @State private var isFrameDrawn = false

    var body: some View {
        switch phase {
        case .simulator:
            LookStandIn(look: look, captionTopInset: captionTopInset)
        case .ready:
            if let previewSource {
                ZStack {
                    CameraPreviewView(source: previewSource)
                        .opacity(look != nil && isFrameDrawn ? 0 : 1)
                    if let look {
                        FrameView(frames: previewSource.frames, look: look) { isFrameDrawn = true }
                            .opacity(isFrameDrawn ? 1 : 0)
                            .onDisappear { isFrameDrawn = false }
                    }
                }
            } else {
                Color.black
            }
        case .scanning, .cameraDenied, .cameraRestricted, .failed, .released:
            Color.black
                .overlay {
                    if let status = StatusText.viewfinder(phase) {
                        StatusOverlay(status: status)
                    }
                }
        }
    }
}
