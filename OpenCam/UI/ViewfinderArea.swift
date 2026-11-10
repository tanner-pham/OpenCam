import SwiftUI

extension EnvironmentValues {
    /// The live session's preview source; nil in the Simulator.
    @Entry var previewSource: PreviewSource?
}

/// The picture area: the live preview when ready, the stand-in in the Simulator, what is wrong in words when there is no camera picture.
struct ViewfinderArea: View {
    let phase: CameraPhase
    var captionTopInset: CGFloat = 0

    @Environment(\.previewSource) private var previewSource

    var body: some View {
        switch phase {
        case .simulator:
            ViewfinderStandIn(captionTopInset: captionTopInset)
        case .ready:
            if let previewSource {
                CameraPreviewView(source: previewSource)
            } else {
                Color.black
            }
        case .scanning, .cameraDenied, .cameraRestricted, .failed:
            Color.black
                .overlay {
                    if let status = StatusText.viewfinder(phase) {
                        StatusOverlay(status: status)
                    }
                }
        }
    }
}
