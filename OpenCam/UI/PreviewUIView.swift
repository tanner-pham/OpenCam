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
    private var previewingObservation: NSKeyValueObservation?
    /// The first-picture line is written once per view.
    private var hasJournaledFirstPicture = false
    private var sessionObservers: [any NSObjectProtocol] = []
    private let frames: FramePipeline

    private let session: AVCaptureSession
    /// The one preview of the running session, kept across layout changes (`CameraPreviewView`).
    private static var current: PreviewUIView?

    private var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    /// The preview for `source`'s session, made on first use and reused after. `OpenCamApp` makes it before the session
    /// starts, so the layer is connected when `startRunning` is called, and `CameraPreviewView` later receives this same view.
    static func shared(for source: PreviewSource) -> PreviewUIView {
        if let current, current.session === source.session { return current }
        let preview = PreviewUIView(source: source)
        current = preview
        return preview
    }

    private init(source: PreviewSource) {
        frames = source.frames
        session = source.session
        super.init(frame: .zero)
        backgroundColor = .black
        guard let previewLayer else {
            Self.logger.error("[PreviewUIView:init] Layer is not a preview layer — {layer: \(String(describing: type(of: self.layer)), privacy: .public)}")
            return
        }
        previewLayer.videoGravity = .resizeAspect
        let attachStart = ContinuousClock.now
        previewLayer.session = source.session
        TimingJournal.record("preview attach", since: attachStart, over: TimingJournal.mainActorThreshold)
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
        // `isPreviewing` is meant to be observed (AVCaptureVideoPreviewLayer.h). The header names no delivery queue, so the
        // callback only hops to the main actor, where the layer and the window are read again.
        previewingObservation = previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.journalFirstPictureIfShown() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotationCoordinator()
        journalFirstPictureIfShown()
    }

    /// Writes `[timing] launch first picture N ms` the first time the layer is rendering frames while the view is in a window.
    private func journalFirstPictureIfShown() {
        guard !hasJournaledFirstPicture, window != nil, previewLayer?.isPreviewing == true else { return }
        hasJournaledFirstPicture = true
        var timeline = LaunchTimeline()
        timeline.mark("first picture")
        ErrorJournal.record(timeline.line)
    }

    /// Builds a coordinator when the layer's camera differs from the one being followed.
    func updateRotationCoordinator() {
        let started = ContinuousClock.now
        defer { TimingJournal.record("preview rotation update", since: started, over: TimingJournal.mainActorThreshold) }
        // The coordinator is made for "a layer displaying the camera's video preview" (AVCaptureDevice.h,
        // initWithDevice:previewLayer:), and the header gives 0 degrees only for no layer. This view now exists before the
        // session starts, with its layer in no window yet; the same-device guard below would then keep a coordinator built
        // too early. `didMoveToWindow` calls this again, which builds it once the view is shown, as before the early attach.
        guard window != nil else { return }
        guard let previewLayer,let device = Self.videoDevice(of: previewLayer) else { return }
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
