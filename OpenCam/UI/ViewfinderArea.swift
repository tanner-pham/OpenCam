import SwiftUI

extension EnvironmentValues {
    /// The live session's preview source; nil in the Simulator.
    @Entry var previewSource: PreviewSource?
}

/// The picture area: the live preview when ready, the stand-in in the Simulator, what is wrong in words when there is no camera picture.
/// With a look on the device, its frames are drawn over the preview, which hides once the first frame is drawn and stays in
/// place (its rotation coordinator turns the frames). Turning a look on or off never rebuilds the preview.
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
