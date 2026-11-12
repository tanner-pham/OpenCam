import AVFoundation
import UIKit

/// A view whose layer is the preview layer of the check's own session.
final class RecorderCheck2PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    /// Attaches the session (nil detaches it) and turns the preview upright for a portrait phone.
    func show(_ session: AVCaptureSession?) {
        guard let previewLayer else { return }
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
