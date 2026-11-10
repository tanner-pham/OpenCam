import AVFoundation
import OSLog
import UIKit

/// Hosts the live picture, aspect-fit, kept horizon-level by a rotation coordinator for the layer's camera. The same
/// coordinator's angle turns the look's frames: the layer stays in the view hierarchy while a look hides it, so its angle
/// stays valid (AVCaptureDevice.h, `previewLayer`).
final class PreviewUIView: UIView {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "Preview")

    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var sessionObservers: [any NSObjectProtocol] = []
    private let frames: FramePipeline

    private var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    init(source: PreviewSource) {
        frames = source.frames
        super.init(frame: .zero)
        backgroundColor = .black
        guard let previewLayer else {
            Self.logger.error("[PreviewUIView:init] Layer is not a preview layer — {layer: \(String(describing: type(of: self.layer)), privacy: .public)}")
            return
        }
        previewLayer.videoGravity = .resizeAspect
        previewLayer.session = source.session
        // A new camera input arrives with the first start, and with each configure on a running session
        // (a lens switch or reconfigure); rebuild the coordinator for it then.
        let center = NotificationCenter.default
        let started = center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: source.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRotationCoordinator() }
        }
        // Each configure may attach another camera to the frames, so they are given the angle again before the coordinator
        // is rebuilt, which happens only for a new camera.
        let configured = center.addObserver(forName: PreviewSource.didConfigureNotification, object: source.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyFrameOrientation()
                self?.updateRotationCoordinator()
            }
        }
        sessionObservers = [started, configured]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotationCoordinator()
    }

    /// Builds a coordinator when the layer's camera differs from the one being followed.
    func updateRotationCoordinator() {
        guard let previewLayer, let device = Self.videoDevice(of: previewLayer) else { return }
        guard rotationCoordinator?.device?.uniqueID != device.uniqueID else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            // The coordinator delivers key-value updates on the main queue (AVCaptureDevice.h).
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            MainActor.assumeIsolated { self?.applyRotation(angle) }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        applyFrameOrientation()
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Hands the preview's horizon-level angle to the frames, which turn each image by it themselves.
    private func applyFrameOrientation() {
        guard let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview else { return }
        frames.setAngle(angle)
    }

    private static func videoDevice(of layer: AVCaptureVideoPreviewLayer) -> AVCaptureDevice? {
        let inputs = layer.connection?.inputPorts.map(\.input) ?? []
        return inputs.lazy.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }?.device
    }
}
