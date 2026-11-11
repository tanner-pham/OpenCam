import SwiftUI

/// The live camera picture. The preview view itself is made once per session and moved into whichever layout shows the
/// picture: a rotation or a mode change swaps the whole layout, and a new preview layer would attach to the running session
/// (a session change on the main thread) and drop its own connection when the old one went. The container is what SwiftUI
/// makes and removes; the replacement is made before the old one is taken down, so taking the old one down never takes the
/// preview from the new one.
struct CameraPreviewView: UIViewRepresentable {
    let source: PreviewSource

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        adopt(PreviewUIView.shared(for: source), into: container)
        return container
    }

    private func adopt(_ preview: PreviewUIView, into container: UIView) {
        preview.frame = container.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(preview)
    }

    func updateUIView(_ container: UIView, context: Context) {
        // A container on screen without the preview lost it to a newer container that has since been taken down; it takes
        // the preview back rather than staying black.
        if container.window != nil, !container.subviews.contains(where: { $0 is PreviewUIView }) {
            adopt(PreviewUIView.shared(for: source), into: container)
        }
        for case let preview as PreviewUIView in container.subviews {
            preview.updateRotationCoordinator()
        }
    }

    static func dismantleUIView(_ container: UIView, coordinator: ()) {
        for case let preview as PreviewUIView in container.subviews {
            preview.removeFromSuperview()
        }
    }
}
