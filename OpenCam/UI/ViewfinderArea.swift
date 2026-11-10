import SwiftUI

extension EnvironmentValues {
    /// The live session's preview source; nil in the Simulator.
    @Entry var previewSource: PreviewSource?
}

/// The picture area: the live preview when ready, the stand-in in the Simulator, a status line while formats are read, black otherwise.
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
        case .scanning:
            Color.black
                .overlay {
                    Text("Reading camera formats…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        case .cameraDenied, .cameraRestricted, .failed:
            Color.black
        }
    }
}
