import SwiftUI

/// The live camera picture.
struct CameraPreviewView: UIViewRepresentable {
    let source: PreviewSource

    func makeUIView(context: Context) -> PreviewUIView {
        PreviewUIView(source: source)
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.updateRotationCoordinator()
    }
}
